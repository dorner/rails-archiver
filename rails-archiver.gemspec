Gem::Specification.new do |s|
  s.name         = 'rails-archiver'
  s.require_paths = %w(. lib lib/rails-archiver)
  s.version      = '0.2.0'
  s.date         = '2025-01-20'
  s.summary      = 'Fully archive a Rails model'
  s.description  = <<-EOF
  EOF
  s.authors      = ['Daniel Orner']
  s.email        = 'daniel.orner@wishabi.com'
  s.files        = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  s.homepage     = 'https://github.com/dorner/rails-archiver'
  s.license = 'MIT'

  s.add_dependency 'rails', '>= 3.0'
  s.add_development_dependency 'aws-sdk-s3', '~> 1.13'

end
