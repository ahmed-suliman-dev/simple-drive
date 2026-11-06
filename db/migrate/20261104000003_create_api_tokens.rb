# Bearer tokens. Only a SHA-256 digest is stored, so a leaked database
# does not leak usable tokens.
class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
  end
end
