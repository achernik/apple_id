RSpec.describe AppleID::IdToken do
  subject { id_token }
  let(:signature_base_string) do
    'eyJraWQiOiJBSURPUEsxIiwiYWxnIjoiUlMyNTYifQ.eyJpc3MiOiJodHRwczovL2FwcGxlaWQuYXBwbGUuY29tIiwiYXVkIjoianAueWF1dGguc2lnbmluLnNlcnZpY2UyIiwiZXhwIjoxNTU5NzA5ODkwLCJpYXQiOjE1NTk3MDkyOTAsInN1YiI6IjAwMDcyMy4yNWRhOGJlMzMyOTY0OTkxODk4NjMwOTQ3MjAyZmVmMC4wNDAyIiwiYXRfaGFzaCI6InpqUmlUN2QzVHFRNVM3cEZkbzZxWGcifQ'
  end
  let(:signature_base_string_with_more_claims) do
    'eyJraWQiOiI4NkQ4OEtmIiwiYWxnIjoiUlMyNTYifQ.eyJpc3MiOiJodHRwczovL2FwcGxlaWQuYXBwbGUuY29tIiwiYXVkIjoianAueWF1dGguc2lnbmluLnNlcnZpY2UzIiwiZXhwIjoxNTg1MTE2NzMyLCJpYXQiOjE1ODUxMTYxMzIsInN1YiI6IjAwMDcyMy4yNWRhOGJlMzMyOTY0OTkxODk4NjMwOTQ3MjAyZmVmMC4wNDAyIiwibm9uY2UiOiI4MDliMzFmM2E4ZDQxOTMwIiwiY19oYXNoIjoiY0JvOXREYkRZOWlrYTFXNlZmTzBCdyIsImVtYWlsIjoiZm9vYmFyQHByaXZhdGVyZWxheS5hcHBsZWlkLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjoidHJ1ZSIsImlzX3ByaXZhdGVfZW1haWwiOiJ0cnVlIiwiYXV0aF90aW1lIjoxNTg1MTE2MTMyLCJub25jZV9zdXBwb3J0ZWQiOnRydWV9'
  end
  let(:signature) do
    'jDV-AVFM-Yx_lxc-hsJNF2mgD2PoRlQ8SJjharKom87pIKR1frQfaY_apO-AxyDrhvB3qOdfhZql08EHBHNWATlX3l6sAKL-bUPH6bzHxIZTWHZ9IOimPyvTOJNFyJWLsm6lGcqemKB1UQG2MQ06lI9qc6C6T8_obv2HPJ-Sm8OBE9z-CDyKGcFZ-R8b2Ut6TibmRyQ-kmB7na6ay9kGXm56I_TeA2QCMJGKH_X8C2M7kBPsO_WrYuogA3tnWLT8wi0TPD5zKnnBH0bXLgjeyE2lYRgboQttX6WqTdR0dN-mLi8ShTPEGUCkC7_jFJH9XpC7LfCeKl9tD3qzC_Dx1Q'
  end
  let(:invalid_signature) do
    Base64.urlsafe_encode64('invalid', padding: false)
  end
  let(:id_token_str) do
    [signature_base_string, signature].join('.')
  end
  let(:id_token) { AppleID::IdToken.decode(id_token_str) }

  its(:original_jwt) { should == JSON::JWT.decode(id_token_str, :skip_verification) }
  its(:original_jwt_string) { should == id_token_str }

  [:email_verified, :is_private_email, :nonce_supported].each do |boolean_claim|
    describe boolean_claim do
      context 'when claim is missing' do
        its(:"#{boolean_claim}?") { should == false  }
      end

      context 'when claim is given' do
        let(:signature_base_string) { signature_base_string_with_more_claims }
        its(:"#{boolean_claim}?") { should == true  }
      end
    end
  end

  describe '.decode' do
    it { should be_a AppleID::IdToken }

    context 'when signature invalid' do
      let(:id_token_str) do
        [signature_base_string, invalid_signature].join('.')
      end

      it do
        expect do
          AppleID::IdToken.decode(id_token_str)
        end.not_to raise_error
      end

      it { should be_a AppleID::IdToken }
    end
  end

  describe '#new' do
    subject do
      AppleID::IdToken.new(claims)
    end
    let(:required_claims) do
      {iss: 'iss', sub: 'sub', aud: 'aud', exp: Time.now, iat: Time.now}
    end

    context 'when real_user_status given' do
      let(:claims) do
        required_claims.merge(real_user_status: 2)
      end
      its(:real_user_status) { should be_instance_of AppleID::IdToken::RealUserStatus }
    end

    context 'otherwise' do
      let(:claims) do
        required_claims
      end
      its(:real_user_status) { should be_nil }
    end
  end

  describe '#verify!' do
    let(:expected_client) do
      AppleID::Client.new(
        identifier: 'jp.yauth.signin.service2',
        team_id: 'team_id',
        key_id: 'key_id',
        private_key: OpenSSL::PKey::EC.generate('prime256v1')
      )
    end
    let(:unexpected_client) do
      AppleID::Client.new(
        identifier: 'client_id',
        team_id: 'team_id',
        key_id: 'key_id',
        private_key: OpenSSL::PKey::EC.generate('prime256v1')
      )
    end

    context 'when no expected claims given' do
      it do
        expect do
          mock_json :get, AppleID::JWKS_URI, 'jwks' do
            travel_to(Time.at id_token.iat) do
              id_token.verify!
            end
          end
        end.not_to raise_error
      end
    end

    context 'when claims are valid' do
      it do
        expect do
          travel_to(Time.at id_token.iat) do
            id_token.verify! client: expected_client, verify_signature: false
          end
        end.not_to raise_error
      end
    end

    context 'when claims are invalid' do
      it do
        expect do
          travel_to(Time.at id_token.iat) do
            id_token.verify!(
              client: unexpected_client,
              nonce: 'invalid',
              state: 'invalid',
              access_token: 'invalid',
              code: 'invalid',
              verify_signature: false
            )
          end
        end.to raise_error AppleID::IdToken::VerificationFailed, 'Claims Verification Failed at [:aud, :s_hash, :at_hash, :c_hash]'
      end

      context 'when issuer is invalid' do
        let(:signature_base_string) do
          'eyJraWQiOiJBSURPUEsxIiwiYWxnIjoiUlMyNTYifQ.eyJpc3MiOiJodHRwczovL3Vua25vd24uZXhhbXBsZS5jb20iLCJhdWQiOiJqcC55YXV0aC5zaWduaW4uc2VydmljZTIiLCJleHAiOjE1NTk3MDk4OTAsImlhdCI6MTU1OTcwOTI5MCwic3ViIjoiMDAwNzIzLjI1ZGE4YmUzMzI5NjQ5OTE4OTg2MzA5NDcyMDJmZWYwLjA0MDIiLCJhdF9oYXNoIjoiempSaVQ3ZDNUcVE1UzdwRmRvNnFYZyJ9'
        end

        it do
          expect do
            travel_to(Time.at id_token.iat) do
              id_token.verify!(
                verify_signature: false
              )
            end
          end.to raise_error AppleID::IdToken::VerificationFailed, 'Claims Verification Failed at [:iss]'
        end
      end

      context 'when future token given' do
        it do
          expect do
            travel_to(Time.at id_token.iat - 1) do
              id_token.verify!(
                verify_signature: false
              )
            end
          end.to raise_error AppleID::IdToken::VerificationFailed, 'Claims Verification Failed at [:iat]'
        end
      end

      context 'when expired token given' do
        it do
          expect do
            id_token.verify!(
              verify_signature: false
            )
          end.to raise_error AppleID::IdToken::VerificationFailed, 'Claims Verification Failed at [:exp]'
        end
      end
    end

    context 'when signature is invalid' do
      let(:id_token_str) do
        [signature_base_string, invalid_signature].join('.')
      end

      context 'when verify_signature=false is given' do
        it do
          expect do
            travel_to(Time.at id_token.iat) do
              id_token.verify! client: expected_client, verify_signature: false
            end
          end.not_to raise_error
        end
      end

      context 'otherwise' do
        it do
          expect do
            mock_json :get, AppleID::JWKS_URI, 'jwks' do
              travel_to(Time.at id_token.iat) do
                id_token.verify! client: expected_client
              end
            end
          end.to raise_error AppleID::IdToken::VerificationFailed, 'Signature Verification Failed'
        end
      end
    end

    context 'when nonce is invalid' do
      context 'when nonce is supported' do
        let(:signature_base_string) { signature_base_string_with_more_claims }
        it do
          expect do
            travel_to(Time.at id_token.iat) do
              id_token.verify! nonce: 'expected', verify_signature: false
            end
          end.to raise_error AppleID::IdToken::VerificationFailed, 'Claims Verification Failed at [:nonce]'
        end
      end

      context 'when nonce is not supported' do
        it do
          expect do
            travel_to(Time.at id_token.iat) do
              id_token.verify! nonce: 'expected', verify_signature: false
            end
          end.not_to raise_error
        end
      end
    end
  end
end
