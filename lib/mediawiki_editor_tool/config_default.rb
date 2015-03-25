module MediawikiEditorTool
  CONFIG_DEFAULT = {
    PROGNAME:		"MediawikiEditorTool",
    VERSION:		"0.1",
    API_URL_LANG:	{
      "en" => "https://en.wikipedia.org/w/api.php"
    },
    API_URL:		"https://en.wikipedia.org/w/api.php",
    DIFFCMD:		"diff",
    DIFFOPTS:		["-u"],
    ARTICLE_FILENAME_EXTENSION: ".wiki"
  }      

  class << self
    def user_agent_string
      "#{Config[:PROGNAME]}/#{Config[:VERSION]} MediawikiApi/#{MediawikiApi::VERSION}"
    end
  end
end
