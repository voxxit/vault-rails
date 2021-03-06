require "vault"

require "base64"
require "json"

require_relative "encrypted_model"
require_relative "rails/configurable"
require_relative "rails/version"

module Vault
  module Rails
    extend Vault::Rails::Configurable

    # API client object based off the configured options in
    # {Vault::Configurable}.
    #
    # @return [Vault::Client]
    def self.client
      if !defined?(@client) || !@client.same_options?(options)
        @client = Vault::Client.new(options)
      end
      return @client
    end

    # Delegate all methods to the client object, essentially making the module
    # object behave like a {Vault::Client}.
    def self.method_missing(m, *args, &block)
      if client.respond_to?(m)
        client.public_send(m, *args, &block)
      else
        super
      end
    end

    # Delegating `respond_to` to the {Vault::Client}.
    def self.respond_to_missing?(m, include_private = false)
      client.respond_to?(m) || super
    end

    # Encrypt the given plaintext data using the provided mount and key.
    #
    # @param [String] path
    #   the mount point
    # @param [String] key
    #   the key to encrypt at
    # @param [String] plaintext
    #   the plaintext to encrypt
    # @param [Vault::Client] client
    #   the Vault client to use
    #
    # @return [String]
    #   the encrypted cipher text
    def self.encrypt(path, key, plaintext, client = self.client)
      if self.enabled?
        return self.vault_encrypt(path, key, plaintext, client)
      end
      return self.memory_encrypt(path, key, plaintext, client)
    end

    # Decrypt the given ciphertext data using the provided mount and key.
    #
    # @param [String] path
    #   the mount point
    # @param [String] key
    #   the key to decrypt at
    # @param [String] ciphertext
    #   the ciphertext to decrypt
    # @param [Vault::Client] client
    #   the Vault client to use
    #
    # @return [String]
    #   the decrypted plaintext text
    def self.decrypt(path, key, ciphertext, client = self.client)
      if self.enabled?
        return self.vault_decrypt(path, key, ciphertext, client)
      end
      return self.memory_decrypt(path, key, ciphertext, client)
    end

    private

    # Perform in-memory encryption. This is useful for testing and development.
    def self.memory_encrypt(path, key, plaintext, client)
      log_warning

      return nil if plaintext.nil?

      cipher = OpenSSL::Cipher::AES.new(128, :CBC)
      cipher.encrypt
      cipher.key = memory_key_for(path, key)
      return Base64.strict_encode64(cipher.update(plaintext) + cipher.final)
    end

    # Perform in-memory decryption. This is useful for testing and development.
    def self.memory_decrypt(path, key, ciphertext, client)
      log_warning

      return nil if ciphertext.nil?

      cipher = OpenSSL::Cipher::AES.new(128, :CBC)
      cipher.decrypt
      cipher.key = memory_key_for(path, key)
      return cipher.update(Base64.strict_decode64(ciphertext)) + cipher.final
    end

    # Perform encryption using Vault. This will raise exceptions if Vault is
    # unavailable.
    def self.vault_encrypt(path, key, plaintext, client)
      return nil if plaintext.nil?

      route  = File.join(path, "encrypt", key)
      secret = client.logical.write(route,
        plaintext: Base64.strict_encode64(plaintext),
      )
      return secret.data[:ciphertext]
    end

    # Perform decryption using Vault. This will raise exceptions if Vault is
    # unavailable.
    def self.vault_decrypt(path, key, ciphertext, client)
      return nil if ciphertext.nil?

      route  = File.join(path, "decrypt", key)
      secret = client.logical.write(route, ciphertext: ciphertext)
      return Base64.strict_decode64(secret.data[:plaintext])
    end

    # The symmetric key for the given params.
    # @return [String]
    def self.memory_key_for(path, key)
      return Base64.strict_encode64("#{path}/#{key}".ljust(32, "x"))
    end

    private

    def self.log_warning
      if defined?(::Rails) && ::Rails.logger != nil
        ::Rails.logger.warn do
          "[vault-rails] Using in-memory cipher - this is not secure " \
          "and should not be used in production-like environments."
        end
      end
    end
  end
end
