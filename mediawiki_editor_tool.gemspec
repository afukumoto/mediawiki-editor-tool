# -*-ruby-*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mediawiki_editor_tool/version'

Gem::Specification.new do |s|
  s.name	= "MediawikiEditorTool"
  s.version	= MediawikiEditorTool::VERSION
  s.authors	= ["Atsushi Fukumoto"]
  s.email	= ["fukumoto@imasy.or.jp"]
  s.summary	= "A tool for Mediawiki users"
  s.description	= "Uses Mediawiki API to access the wiki articles, including Wikipedia."
  s.homepage	= "https://github.com/afukumoto/mediawiki-editor-tool"
  s.license	= 'MIT'
  s.executables	<< "met"
  s.files	= `git ls-files`.split
  s.add_runtime_dependency "mediawiki_api", '~> 0.3'
end
