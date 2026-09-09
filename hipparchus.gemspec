# frozen_string_literal: true

require_relative "lib/hipparchus/version"

Gem::Specification.new do |spec|
  spec.name = "hipparchus"
  spec.version = Hipparchus::VERSION
  spec.authors = ["Drew Hund"]
  spec.email = ["languageinvestigator@gmail.com"]

  spec.summary = "A gem for creating Entity Relationship Diagrams (ERDs) from a database schema."
  spec.description = "Takes a database schema and generates an Entity Relationship Diagram (ERD) in various " \
                     "formats, including PNG, SVG, and PDF. Supports multiple database types and allows " \
                     "customization of the generated diagrams."
  spec.homepage = "https://www.github.com/EphemSpirit/hipparchus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://www.github.com/EphemSpirit/hipparchus"
  spec.metadata["changelog_uri"] = "https://www.github/comEphemSpirit/hipparchus/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Schema extraction leans on an ActiveRecord connection handed in by the
  # caller for adapter identification and database metadata.
  spec.add_dependency "activerecord", ">= 7.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
