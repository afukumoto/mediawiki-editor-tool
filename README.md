# MediawikiEditorTool

MediawikiEditorTool is a command line interface to help editing Mediawiki articles, such as Wikipedia.  It is intended to look like version control system, such as git or svn.

## Build

```
$ gem build mediawiki_editor_tool.gemspec
```

## Install

```
$ gem install ./MediawikiEditorTool-0.0.1.gem
```

## Usage

    met [-l LANG] [-u URL] subcommand [arguments...]

Use the command `met` with subcommands `login`, `checkout`, `preview`, `commit`, `log`, `revision`, `diff`, `status`.

By default, met command accesses https://en.wikipedia.org/.  Option `-l LANG` is to choose the language of Wikipedia site.

Use option `-u URL` to specify the Mediawiki API URL explictly.

Wiki articles are specified with its titles, and local files will be named with ".wiki" suffixes after the title.  For example, "Wikipedia:Sandbox" will be stored locally in the file `Wikipedia:Sandbox.wiki`.
If section edit is specified, the local file with an extension ".section" and the section number is used.  For example, section 1 of "Wikipedia:Sandbox" is stored in `Wikipedia:Sandbox.section1.wiki`.

`met` command creates a directory named `.MediawikiEditorTool` in the current directory to store the article information.

## Subcommands

### login

    met login [username]

Log in to the Mediawiki with specified username.  Enter the password to the password prompt.  Log-in information is stored in the ./.MediawikiEditorTool/cookie file.

You can use other commands without login.  In that case you will be accessing as IP-user.

### checkout

    met checkout [-f] [-s SECTION] title

Article text will be retrieved and stored as a local file in the current directory.  You can edit the file, and use `commit` subcommand to send the edited text to update the article.

Also, checkout command can be used to update the text to the newest revision.

If there is a local file of the same name in the current directory, `checkout` fails.  Use `-f` option to force overwrite.

Option `-s` specifies the section edit.  SECTION must be the number, and the section text is written to a local file into a filename with ".section" and the section number added.

### preview

    met preview title

Preview the locally edited file using an external HTML browser (`firefox` by default).  At the moment, the rendered HTML will look poor since the style sheets and image files are not available for preview.

### commit

    met commit [-m] [-s SUMMARY] title

Edited article text will be sent to Mediawiki server.  Option `-m` to specify "minor edit" flag.  Option `-s SUMMARY` to specify the edit summary description.

### log

    met log [-l LOGLENGTH] title

Prints the revision history of the article to the standard output.
The format of output is:
> REVISION-ID TIMESTAMP USERNAME SIZE COMMENT

### revision

    met revision [-r REVISION] [-s SECTION] title

Prints the specified revision of the article to the standard output.  Option `-r REVISION` specifies the revision ID.  If no revision is specified, the newest revision is printed.

If `-s` option is specified, the section text with specified section number is printed.

### diff

    met diff [-r REVISION1 [-r REVISION2]] [-s SECTION] title

Compares specified revisions of the article text.  If no `-r` option is specified, it compares the local text with the base revision text.  If one `-r` option is specified, the local text is compared to the specified reivision text.  If two `-r` options are specified, those two revisions are compared.

If `-s` is to compare the text of specified section.

### status

    met status [title...]

Prints the status of titles.  If no titles are specified, all files in the current directory whose name does not start with "." will be checked.
The output format is:
> FLAG REVISION-ID TITLE

FLAG| Meaning
----|:-------------------
?   | Unknown 
U   | Server has newer revision
M   | Local file modified
C   | Both server and local file modified
=| Local file is identical to newest revision

## Config

Some configuration parameters can be changed by creating `.MediawikiEditorTool/config` file.  It is a JSON format file.

## TODO

* `-l LANG` and `-u URL` options are not remembered to subsequent use of met.  You need to specify it every time.

* Support `-l LANG` other than `en`
