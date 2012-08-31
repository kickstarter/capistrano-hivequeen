require File.expand_path('./lib/capistrano/hivequeen/version.rb')

Gem::Specification.new do |s|
  s.specification_version = 2 if s.respond_to? :specification_version=
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=

  ## Leave these as is they will be modified for you by the rake gemspec task.
  ## If your rubyforge_project name is different, then edit it and comment out
  ## the sub! line in the Rakefile
  s.name              = 'capistrano-hivequeen'
  s.version           = HiveQueen::Version.to_s
  s.date              = Time.now.strftime("%Y-%m-%d")

  ## Make sure your summary is short. The description may be as long
  ## as you like.
  s.summary     = "Capistrano extensions for interacting with HiveQueen"
  s.description = "Capistrano extensions for interacting with HiveQueen"

  ## List the primary authors. If there are a bunch of authors, it's probably
  ## better to set the email to an email list or something. If you don't have
  ## a custom homepage, consider using your GitHub URL or the like.
  s.authors  = ["Aaron Suggs"]
  s.email    = 'aaron@kickstarter.com'
  s.homepage = 'http://github.com/kickstarter/capistrano-hivequeen'

  ## This sections is only necessary if you have C extensions.
  # s.require_paths << 'ext'
  # s.extensions = %w[ext/extconf.rb]

  ## If your gem includes any executables, list them here.
  s.executables = []

  ## Specify any RDoc options here. You'll want to add your README and
  ## LICENSE files to the extra_rdoc_files list.
  s.rdoc_options = ["--charset=UTF-8"]
  s.extra_rdoc_files = %w[README.rdoc]

  ## List your runtime dependencies here. Runtime dependencies are those
  ## that are needed for an end user to actually USE your code.
  s.add_dependency('capistrano', '>= 2.11.0')
  s.add_dependency('json')
  s.add_dependency('excon', '>= 0.6.0') # Perhaps we can support older. Haven't checked.

  ## List your development dependencies here. Development dependencies are
  ## those that are only needed during development
  #s.add_development_dependency('rake')

  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- {spec,tests}/*`.split("\n")
end
