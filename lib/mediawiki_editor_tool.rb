
require 'mediawiki_api'
require 'mediawiki_api/version'
require 'mediawiki_editor_tool/version'
require 'mediawiki_editor_tool/config'
require 'mediawiki_editor_tool/config_default'
require 'optparse'
require 'json'
require 'fileutils'
require 'tempfile'
require 'time'
require 'digest'
require 'pp' if $DEBUG

module MediawikiEditorTool
  TEMPFILEPREFIX = 'met'

  MET_DIR = ".MediawikiEditorTool"
  CONFIG_FILE_NAME = "config"
  META_DIR_NAME = "pages"
  COOKIE_FILE_NAME = "cookie"

  class Page
    class << self
      def metafilepath(title)
        File.join(MET_DIR, META_DIR_NAME, title)
      end
    end

    def initialize(meta = nil)
      @meta = meta
    end

    def from_response(resp)
      pages = resp.data['pages']
      @meta = pages[pages.keys[0]]
      self
    end

    def from_metafile(title)
      @meta = File.open(Page::metafilepath(title), "r:utf-8") { |file|
        JSON.parse(file.read)
      }
      self
    rescue
      nil
    end

    def save_meta
      FileUtils.mkdir_p(File.join(MET_DIR, "pages"))
      File.open(Page::metafilepath(title), "w:utf-8") do |file|
        file.write(JSON.generate(@meta))
      end
    end

    def pageid
      @meta['pageid']
    end

    def title
      @meta['title']
    end

    def revisions
      @meta['revisions']
    end

    def text
      revisions[0]['*']
    end

    def revid
      revisions[0]['revid']
    end

    def basetimestamp
      revisions[0]['timestamp']
    end
  end

  class Client < MediawikiApi::Client
    # override MediawikiApi::Client.initialize to set @cookie_jar and headers
    def initialize(url, log = false)
      @cookie_jar = HTTP::CookieJar.new
      headers = { 'User-Agent' => MediawikiEditorTool::user_agent_string }
      @conn = Faraday.new(url: url, headers: headers) do |faraday|
        faraday.request :multipart
        faraday.request :url_encoded
        faraday.response :logger if log
        faraday.use :cookie_jar, jar: @cookie_jar
        faraday.adapter Faraday.default_adapter
      end
      @logged_in = false
      @tokens = {}
    end

    def get_page(title, params = {})
      params['rvprop'] ||= 'content|ids|timestamp|sha1'
      params['titles'] ||= title
      reply = self.prop(:revisions, params)
      reply.success? or abort "failed to retrieve"
      page = Page.new.from_response(reply)
      page
    end

    def get_revision(title, revision)
      get_page(title, rvstartid: revision, rvendid: revision)
    end

    def get_log(title, revnum = nil)
      params = {titles: title, rvprop: 'ids|flags|timestamp|user|comment|size', continue: ''}
      params['rvlimit'] = revnum.to_s if revnum
      reply = self.prop(:revisions, params)
      reply.success? or abort "failed to retrieve"
      pp reply if $DEBUG
      # p reply.data
      Page.new.from_response(reply)
    end

    def load_cookie(file)
      @cookie_jar.load(file)
    end

    def save_cookie(file)
      @cookie_jar.save(file)
    end
  end

  class << self
    def article_filename(title)
      title + Config[:ARTICLE_FILENAME_EXTENSION]
    end

    def check_title(title)
      if title =~ /\//
        abort "title should not contain slash"
      end
      if title =~ /\|/
        abort "title should not contain vertical bar"
      end
      title.sub(/#{Config[:ARTICLE_FILENAME_EXTENSION]}$/o, "")
    end

    def cookie_filename
      File.join(MET_DIR, COOKIE_FILE_NAME)
    end

    def not_null(obj)
      obj.to_s != ''
    end

    def diff(filepath1, filepath2)
      system(Config[:DIFFCMD], *Config[:DIFFOPTS], filepath1, filepath2)
    end

    def main
      if Encoding.default_external == Encoding::US_ASCII
        Encoding.default_external = Encoding::UTF_8
      end
      Encoding.default_internal = Encoding::UTF_8

      FileUtils::mkdir_p MET_DIR

      Config.load

      lang = 'en'
      api_url = nil
      argv = ARGV;

      opts = OptionParser.new
      opts.on('-l', '--lang=LANG') { |arg| lang = arg }
      opts.on('-u', '--url=API_URL') { |arg| api_url = arg }
      opts.order!(argv)

      # API_URL precedence:
      #   -u API_URL
      #   -l LANG
      #   Config[:API_URL]
      api_url ||= Config[:API_URL_LANG][lang] or abort "Unknown language '#{lang}'"
      api_url ||= Config[:API_URL] or abort "No API_URL specified"

      api = MediawikiEditorTool::Client.new(api_url)
      begin
        File.open(cookie_filename, "r") do |file|
          api.load_cookie(file)
        end
      rescue Errno::ENOENT
      end

      cmd = argv.shift

      case cmd
      when "login"
        username = argv.shift
        if ! username
          print "Username: "
          username = gets or abort "Aborting"
          username.chomp!
        end
        print "Password:"
        begin
          system "stty -echo"
          password = gets or abort "Aborting"
          password.chomp!
        ensure
          system "stty echo"
          print "\n"
        end
        api.log_in(username, password)

      when "checkout"
        force = false
        opts = OptionParser.new
        opts.on('-f') { |v| force = v }
        opts.order!(argv)

        title = argv.shift or abort "Need title"
        title = check_title(title)
        if ! force && File.exist?(article_filename(title))
          working_page = Page.new.from_metafile(title)
          if ! working_page
            abort "File exists.  Use -f to force overwrite."
          end
          if working_page.text != File.read(article_filename(title))
            abort "Working file modified.  Use -f to force overwrite."
          end
        end

        page = api.get_page(title)
        page.save_meta
        File.open(article_filename(title), "w") do |file|
          file.write(page.text)
        end

      when "log"
        loglen = 10
        opts = OptionParser.new
        opts.on('-l LOGLENGTH') { |v| loglen = v }
        opts.order!(argv)

        title = argv.shift or abort "Need title"
        title = check_title(title)
        log = api.get_log(title, loglen) or abort "Unknown title"
        # print "pageid: #{log.pageid]}, title: #{log.title]}\n"
        # print "revisions:\n"
        # p log['revisions'][0]
        log.revisions.each do |rev|
          # default props: revid parentid minor user timestamp comment
          print "  "
          printf "%9s %s %-17s %5d", rev['revid'], rev['timestamp'], rev['user'], rev['size']
          print " \"#{rev['comment']}\"" if not_null(rev['comment'])
          print "\n"
        end

      when "commit"
        summary = ""
        minor = false

        opts = OptionParser.new
        opts.on('-s SUMMARY') { |v| summary = v }
        opts.on('-m') { |v| minor = true }
        opts.order!(argv)
        title = argv.shift or abort "Need title"
        title = check_title(title)

        working_page = Page.new.from_metafile(title) or abort "Unknown title"

        text = File.read(article_filename(title))
        api.edit(title: title,
                 text: text,
                 summary: summary,
                 basetimestamp: working_page.basetimestamp, 
                 starttimestamp: File.mtime(Page::metafilepath(title)).getutc.xmlschema,
                 md5: Digest::MD5.hexdigest(text))

      when "revision"
        rev = nil
        opts = OptionParser.new
        opts.on('-r REVISION') { |v| rev = v }
        opts.order!(argv)

        title = argv.shift or abort 'Need title'
        title = check_title(title)

        if rev
          page = api.get_revision(title, rev)
        else
          page = api.get_page(title)
        end

        print page.text

      when "diff"
        revs = []
        opts = OptionParser.new
        opts.on('-r REVISION') { |v| revs << v }
        opts.order!(argv)

        title = argv.shift or abort 'Need title'
        title = check_title(title)

        case revs.size
        when 0
          # compare base revision against working file
          page = Page.new.from_metafile(title) or abort 'Not a checked-out title'

          origpage = Tempfile.open(TEMPFILEPREFIX)
          origpage.write(page.text)
          origpage.close(false)

          diff(origpage.path, article_filename(title))

        when 1
          # compare specified reivision against working file
          page = api.get_revision(title, revs[0]) or abort 'Unknown title'
          abort 'Unknown revision' if page.revisions == nil || page.revisions.size == 0

          origpage = Tempfile.open(TEMPFILEPREFIX)
          origpage.write(page.text)
          origpage.close(false)

          diff(origpage.path, article_filename(title))

        when 2
          # compare specified two revisions
          rev1 = api.get_revision(title, revs[0]) or abort 'Unknown title'
          abort "Unknown revision #{revs[0]}" if rev1.revisions == nil || rev1.revisions.size == 0
          rev1file = Tempfile.open(TEMPFILEPREFIX)
          rev1file.write(rev1.text)
          rev1file.close(false)

          rev2 = api.get_revision(title, revs[1]) or abort 'Unknown title'
          abort "Unknown revision #{revs[1]}" if rev2.revisions == nil || rev2.revisions.size == 0
          rev2file = Tempfile.open(TEMPFILEPREFIX)
          rev2file.write(rev2.text)
          rev2file.close(false)

          diff(rev1file.path, rev2file.path)

        else
          abort "Too many -r options."
        end

      when "status"
        titles = argv
        if titles.size == 0
          # If no titles are specified, show statuses for the files in current directory
          titles = Dir.entries('.').sort.select{|fname| fname[0] != "." && FileTest.file?(fname) }
        end
        titles.each do |title|
          title = check_title(title)

          working_page = Page.new.from_metafile(title)
          repository_info = api.get_log(title, 1)

          unknown = false
          modified = false
          update = false

          if ! working_page || ! repository_info
            unknown = true 
          else
            modified = (working_page.text != File.read(article_filename(title)))
            update = (repository_info.revid != working_page.revid)
          end

          status = (unknown ? '?' :
                    (!modified && update) ? 'U' :
                    (modified && !update) ? 'M' :
                    (modified && update) ? 'C' :
                    '=')
          revid = (unknown ? ""  : working_page.revid)
          printf "%s %9s %s\n", status, revid, title
        end

      when "purgecache"
        title = argv.shift or abort "Need title"
        title = check_title(title)
        api.action("purge", titles: title);

      else
        abort "Unknown command"
      end

      File.open(cookie_filename, "w", 0600) do |cookie_file|
        api.save_cookie(cookie_file)
      end
    end
  end
end


