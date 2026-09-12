# frozen_string_literal: true

require "active_record"

# Helpers for the specs that need a real database. The PostgreSQL extractor spec
# connects through ActiveRecord to the URL in HIPPARCHUS_TEST_DATABASE_URL and
# skips itself when that is unset or unreachable.
module HipparchusTest
  DATABASE_URL_ENV = "HIPPARCHUS_TEST_DATABASE_URL"

  module_function

  # @return [String, nil]
  def postgres_url
    url = ENV[DATABASE_URL_ENV]
    url unless url.nil? || url.empty?
  end

  # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter, nil]
  def postgres_connection
    return unless postgres_url

    ActiveRecord::Base.establish_connection(postgres_url)
    connection = ActiveRecord::Base.connection
    connection.verify!
    connection
  rescue StandardError, LoadError => e
    warn "[hipparchus] skipping PostgreSQL specs: #{e.class}: #{e.message}"
    nil
  end
end
