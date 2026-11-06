namespace :api_tokens do
  desc "Generate a new API token. Usage: bin/rails \"api_tokens:create[my-laptop]\""
  task :create, [:name] => :environment do |_task, args|
    name = args[:name].presence || "default"
    _record, token = ApiToken.generate!(name: name)

    puts "Created API token \"#{name}\". Copy it now; it will not be shown again:"
    puts
    puts "  #{token}"
    puts
    puts "Use it as: Authorization: Bearer #{token}"
  end

  desc "List API token names"
  task list: :environment do
    ApiToken.order(:created_at).each do |token|
      puts "#{token.id}\t#{token.name}\tcreated #{token.created_at.iso8601}\tlast used #{token.last_used_at&.iso8601 || 'never'}"
    end
  end
end
