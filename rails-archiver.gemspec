Gem::Specification.new do |s|
  s.name         = 'rails-archiver'
  s.require_paths = %w(. lib lib/rails-archiver)
  s.version      = '0.1.1'
  s.date         = '2016-03-19'
  s.summary      = 'Fully archive a Rails model'
  s.description  = <<-EOF
EOF
  s.authors      = ['Daniel Orner']
  s.email        = 'daniel.orner@wishabi.com'
  s.files        = `git ls-files`.split($/)
  s.homepage     = 'https://github.com/dorner/rails-archiver'
  s.license       = 'MIT'

  s.add_dependency 'rails', '>= 3.0'
  s.add_dependency 'aws-sdk', '~> 2.6'

end