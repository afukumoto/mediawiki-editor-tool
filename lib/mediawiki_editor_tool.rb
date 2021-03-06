
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

  SECTION_EXT = ".section"

  class Page
    class << self
      def metafilepath(title, section = nil)
        File.join(MET_DIR, META_DIR_NAME, MediawikiEditorTool::escape_filename(title) + (section ? SECTION_EXT + ("%d" % section) : ''))
      end
    end

    def initialize(meta = nil)
      @meta = meta
      @section = nil
    end

    attr_writer :section

    def from_response(resp)
      pages = resp.data['pages']
      @meta = pages[pages.keys[0]]
      self
    end

    def from_metafile(title_str, section)
      @meta = File.open(Page::metafilepath(title_str, section), "r:utf-8") { |file|
        JSON.parse(file.read)
      }
      @section = section
      self
    rescue Errno::ENOENT
      nil
    end

    def metafilepath
      Page::metafilepath(title, @section)
    end

    def save_meta
      FileUtils.mkdir_p(File.join(MET_DIR, "pages"))
      File.open(metafilepath, "w:utf-8") do |file|
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
    def get_page(title, params = {})
      params['rvprop'] ||= 'content|ids|timestamp|sha1'
      params['titles'] ||= title
      reply = self.prop(:revisions, params)
      reply.success? or abort "failed to retrieve"
      page = Page.new.from_response(reply)
      page
    end

    def get_section(title, section)
      page = get_page(title, rvsection: section)
      page.section = section
      page
    end

    def get_revision(title, revision, section)
      params = { rvstartid: revision, rvendid: revision }
      params[:rvsection] = section if section
      page = get_page(title, params)
      page.section = section if section
      page
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

    def each_revision(title, params = {})
      params[:titles] ||= title
      params[:rvprop] ||= 'ids|flags|timestamp|user|comment|size'
      params[:rvlimit] ||= 500
      params[:continue] = ''
      loop {
        reply = self.prop(:revisions, params)
        reply.success? or abort "failed to retrieve"
        log = Page.new.from_response(reply)
        log.revisions.each do |r|
          pp r if $DEBUG
          yield r
        end
        p reply['continue'] if $DEBUG
        break if reply['continue'] == nil || reply['continue']['rvcontinue'] == nil
        params[:rvcontinue] = reply['continue']['rvcontinue']
      }
    end

    def revision_by_date(title, datestr)
      date = DateTime.parse(datestr)
      self.each_revision(title) do |rev|
        revdate = DateTime.parse(rev['timestamp'])
        if revdate <= date
          return rev['revid']
        end
      end
      nil
    end

    def get_preview(text)
      params = {
        text: text,
        contentmodel: "wikitext",
        token_type: false
      }
      reply = self.action(:parse, params)
      reply.success? or abort "failed to retrieve"
      pp reply if $DEBUG
      data = reply.data['text'] or return nil
      html = data['*'] or return nil
    end

    def load_cookie(file)
      cookies.load(file)
    end

    def save_cookie(file)
      cookies.save(file)
    end
  end

  class << self
    def escape_filename(str)
      str.gsub(/[%#{File::SEPARATOR}]/, 
               {
                 '%' => '%%',
                 File::SEPARATOR => ("%%%02X" % File::SEPARATOR.ord)
               })
    end

    def article_filename(title, section)
      if section
        escape_filename(title) + SECTION_EXT + ("%d" % section) + Config[:ARTICLE_FILENAME_EXTENSION]
      else
        escape_filename(title) + Config[:ARTICLE_FILENAME_EXTENSION]
      end
    end

    def check_title(title)
      section = nil
      title = title.sub(/#{Regexp.quote(Config[:ARTICLE_FILENAME_EXTENSION])}$/, "")
      title = title.sub(/#{Regexp.quote(SECTION_EXT)}(\d+)$/) { |str| section = $1.to_i; "" }
      title = title.gsub(/(%%|%\h+|%)/) { |match|
        case match
        when "%%"
          "%"
        when "%"
          abort "Unexpected % in title.  Use %% in place of %."
        else
          match[1,2].hex.chr
        end
      }
      if title =~ /[\#\<\>\[\]\|\{\}]/
        abort "Title should not contain '#{$&}' character."
      end
      ## p [title, section] if $DEBUG
      [title, section]
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

    def browse(path)
      system(Config[:BROWSER], path)
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
        section_arg = nil
        opts = OptionParser.new
        opts.on('-f') { |v| force = v }
        opts.on('-s SECTION') { |v| section_arg = v }
        opts.order!(argv)

        title = argv.shift or abort "Need title"
        title, section = check_title(title)
        if section_arg
          section = section_arg
        end

        if section
          page = api.get_section(title, section)
        else
          page = api.get_page(title)
        end

        ##
        ## page title may be different from the requested title due to normalization
        ## 

        if ! force && File.exist?(article_filename(page.title, section))
          working_page = Page.new.from_metafile(page.title, section)
          if ! working_page
            abort "File exists.  Use -f to force overwrite."
          end
          if working_page.text != File.read(article_filename(page.title, section))
            abort "Working file modified.  Use -f to force overwrite."
          end
        end

        page.save_meta
        File.open(article_filename(page.title, section), "w") do |file|
          file.write(page.text)
        end

      when "log"
        loglen = 10
        opts = OptionParser.new
        opts.on('-l LOGLENGTH') { |v| loglen = v.to_i }
        opts.order!(argv)

        title = argv.shift or abort "Need title"
        title, = check_title(title)
        api.each_revision(title) do |rev|
          loglen -= 1
          break if loglen < 0

          # default props: revid parentid minor user timestamp comment
          print "  "
          printf "%9s %s %-17s %5d %s", rev['revid'], rev['timestamp'], rev['user'], rev['size'], (rev['minor'] ? 'm' : '.')
          print " \"#{rev['comment']}\"" if not_null(rev['comment'])
          print "\n"
        end

      when "toc"
        title = argv.shift or abort "Need title"
        title, section = check_title(title)

        reply = api.action(:parse, 
                           page: title,
                           prop: "sections",
                           token_type: false)
        reply.success? or abort "Failed to retrieve"
        sections = reply.data['sections'] or abort "Failed to parse"
        sections.each do |sec|
          pp sec if $DEBUG
          printf " %d:%s%s %s\n",
                 sec['index'].to_i,
                 " " * (2 * sec['toclevel'].to_i),
                 sec['number'],
                 sec['line']
        end

      when "preview"
        title = argv.shift or abort "Need title"
        title, section = check_title(title)

        text = File.read(article_filename(title, section))
        html = api.get_preview(text) or abort "Failed to obtain preview data"

        filepath = File.expand_path(Config[:PREVIEW_FILE_NAME])
        File.write(filepath, html)
        browse(filepath)

      when "commit"
        summary = ""
        minor = false

        opts = OptionParser.new
        opts.on('-s SUMMARY') { |v| summary = v }
        opts.on('-m') { |v| minor = true }
        opts.order!(argv)
        title = argv.shift or abort "Need title"
        title, section = check_title(title)

        working_page = Page.new.from_metafile(title, section) or abort "Unknown title"

        ##
        ## send new file
        ##
        text = File.read(article_filename(title, section))
        params = {
          title: title,
          text: text,
          summary: summary,
          basetimestamp: working_page.basetimestamp, 
          starttimestamp: File.mtime(working_page.metafilepath).getutc.xmlschema,
          md5: Digest::MD5.hexdigest(text)
        }
        params[:section] = section if section
        params[:minor] = '' if minor
        reply = api.edit(params)

        pp reply if $DEBUG

        ##
        ## update metadata to new revision
        ##
        newrevid = reply.data['newrevid'] or abort "Commit succeeded, but the response was not an expected format."
        puts "newrevid: #{newrevid}" if $DEBUG

        page = api.get_revision(title, newrevid, section) or abort "Failed to retrieve new revision"
        page.save_meta

      when "revision"
        rev = nil
        revdate = nil
        section_arg = nil
        opts = OptionParser.new
        opts.on('-r REVISION') { |v| rev = v }
        opts.on('-D DATETIME') { |v| revdate = v }
        opts.on('-s SECTION') { |v| section_arg = v }
        opts.order!(argv)

        title = argv.shift or abort 'Need title'
        title, section = check_title(title)

        if section_arg
          section = section_arg
        end
        if revdate
          rev = api.revision_by_date(title, revdate) or abort 'No revision for the specified date'
        end
        if rev
          page = api.get_revision(title, rev, section)
        elsif section
          page = api.get_section(title, section)
        else
          page = api.get_page(title)
        end

        print page.text

      when "diff"
        revs = []
        section_arg = nil
        opts = OptionParser.new
        opts.on('-r REVISION') { |v| revs << v }
        opts.on('-s SECTION') { |v| section_arg = v }
        opts.order!(argv)

        title = argv.shift or abort 'Need title'
        title, section = check_title(title)
        if section_arg
          section = section_arg
        end

        case revs.size
        when 0
          # compare base revision against working file
          page = Page.new.from_metafile(title, section) or abort 'Not a checked-out title'

          origpage = Tempfile.open(TEMPFILEPREFIX)
          origpage.write(page.text)
          origpage.close(false)

          diff(origpage.path, article_filename(title, section))

        when 1
          # compare specified reivision against working file
          page = api.get_revision(title, revs[0], section) or abort 'Unknown title'
          abort 'Unknown revision' if page.revisions == nil || page.revisions.size == 0

          origpage = Tempfile.open(TEMPFILEPREFIX)
          origpage.write(page.text)
          origpage.close(false)

          diff(origpage.path, article_filename(title, section))

        when 2
          # compare specified two revisions
          rev1 = api.get_revision(title, revs[0], section) or abort 'Unknown title'
          abort "Unknown revision #{revs[0]}" if rev1.revisions == nil || rev1.revisions.size == 0
          rev1file = Tempfile.open(TEMPFILEPREFIX)
          rev1file.write(rev1.text)
          rev1file.close(false)

          rev2 = api.get_revision(title, revs[1], section) or abort 'Unknown title'
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
          title, section = check_title(title)

          working_page = Page.new.from_metafile(title, section)
          repository_info = api.get_log(title, 1)

          unknown = false
          modified = false
          update = false

          if ! working_page || ! repository_info
            unknown = true 
          else
            modified = (working_page.text != File.read(article_filename(title, section)))
            update = (repository_info.revid != working_page.revid)
          end

          status = (unknown ? '?' :
                    (!modified && update) ? 'U' :
                    (modified && !update) ? 'M' :
                    (modified && update) ? 'C' :
                    '=')
          revid = (unknown ? ""  : working_page.revid)
          printf "%s %9s %s%s\n", status, revid, title, (section ? " section #{section}" : '')
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


