module MediawikiEditorTool
  CONFIG_DEFAULT = {
    PROGNAME:		"MediawikiEditorTool",
    API_URL_LANG:	{
      "en" => "https://en.wikipedia.org/w/api.php"
    },
    API_URL:		"https://en.wikipedia.org/w/api.php",
    DIFFCMD:		"diff",
    DIFFOPTS:		["-u"],
    ARTICLE_FILENAME_EXTENSION: ".wiki",
    PREVIEW_FILE_NAME:	"preview.html",
    BROWSER:		"firefox"
  }      

  class << self
    def user_agent_string
      "#{Config[:PROGNAME]}/#{MediawikiEditorTool::VERSION} MediawikiApi/#{MediawikiApi::VERSION}"
    end
  end
end
