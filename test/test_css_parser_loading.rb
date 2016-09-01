require File.expand_path(File.dirname(__FILE__) + '/test_helper')

# Test cases for the CssParser's loading functions.
class CssParserLoadingTests < Minitest::Test
  include CssParser
  include WEBrick

  def setup
    # from http://nullref.se/blog/2006/5/17/testing-with-webrick
    @cp = Parser.new

    @uri_base = 'http://localhost:12000'

    @www_root = File.dirname(__FILE__) + '/fixtures/'

    @server_thread = Thread.new do
      s = WEBrick::HTTPServer.new(:Port => 12000, :DocumentRoot => @www_root, :Logger => Log.new(nil, BasicLog::FATAL), :AccessLog => [])
      s.mount_proc('/redirect301') do |request, response|
        response['Location'] = '/simple.css'
        raise WEBrick::HTTPStatus::MovedPermanently
      end
      s.mount_proc('/redirect302') do |request, response|
        response['Location'] = '/simple.css'
        raise WEBrick::HTTPStatus::TemporaryRedirect
      end
      @port = s.config[:Port]
      begin
        s.start
      ensure
        s.shutdown
      end
    end

    sleep 1 # ensure the server has time to load
  end

  def teardown
    @server_thread.kill
    @server_thread.join(5)
    @server_thread = nil
  end

  def test_loading_301_redirect
    @cp.load_uri!("#{@uri_base}/redirect301")
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_loading_302_redirect
    @cp.load_uri!("#{@uri_base}/redirect302")
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_loading_a_local_file
    file_name = File.dirname(__FILE__) + '/fixtures/simple.css'
    @cp.load_file!(file_name)
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_loading_a_local_file_with_scheme
    file_name = 'file://' + File.expand_path(File.dirname(__FILE__)) + '/fixtures/simple.css'
    @cp.load_uri!(file_name)
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_loading_a_remote_file
    @cp.load_uri!("#{@uri_base}/simple.css")
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  # http://github.com/premailer/css_parser/issues#issue/4
  def test_loading_a_remote_file_over_ssl
    # TODO: test SSL locally
    if RUBY_PLATFORM == 'java'
      skip "SSL: does not work on jruby"
    else
      @cp.load_uri!("https://dialect.ca/inc/screen.css")
      assert_match( /margin\: 0\;/, @cp.find_by_selector('body').join(' ') )
    end
  end

  def test_loading_a_string
    @cp.load_string!("p{margin:0px}")
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_following_at_import_rules_local
    base_dir = File.dirname(__FILE__) + '/fixtures'
    @cp.load_file!('import1.css', base_dir)

    # from '/import1.css'
    assert_equal 'color: lime;', @cp.find_by_selector('div').join(' ')

    # from '/subdir/import2.css'
    assert_equal 'text-decoration: none;', @cp.find_by_selector('a').join(' ')

    # from '/subdir/../simple.css'
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_following_at_import_rules_remote
    @cp.load_uri!("#{@uri_base}/import1.css")

    # from '/import1.css'
    assert_equal 'color: lime;', @cp.find_by_selector('div').join(' ')

    # from '/subdir/import2.css'
    assert_equal 'text-decoration: none;', @cp.find_by_selector('a').join(' ')

    # from '/subdir/../simple.css'
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_imports_disabled
    cp = Parser.new(:import => false)
    cp.load_uri!("#{@uri_base}/import1.css")

    # from '/import1.css'
    assert_equal 'color: lime;', cp.find_by_selector('div').join(' ')

    # from '/subdir/import2.css'
    assert_equal '', cp.find_by_selector('a').join(' ')

    # from '/subdir/../simple.css'
    assert_equal '', cp.find_by_selector('p').join(' ')
  end

  def test_following_remote_import_rules
    css_block = '@import "http://example.com/css";'

    assert_raises CssParser::RemoteFileError do
      @cp.add_block!(css_block, :base_uri => "#{@uri_base}/subdir/")
    end
  end

  def test_allowing_at_import_rules_from_add_block
    css_block = "@import 'https://font.test.com/css?family=font+test';"

    parser = Parser.new
    parser.add_block!(css_block, :ignore_import => false)

    assert_equal true, css_block.include?("@import")
  end

  def test_ignoring_at_import_rules_from_add_block
    css_block = "@import 'https://font.test.com/css?family=font+test';"

    parser = Parser.new
    parser.add_block!(css_block, :ignore_import => true)

    assert_equal false, css_block.include?("@import")
  end

  ############ This Comment is for the next two tests: ##############
  # test_allowing_font_face_rule and test_not_allowing_font_face_rule
  #
  # If font-face is allowed and the css block contains font-face
  # then put all block in one line and remove new lines,
  # the css parser cant handle @font-face otherwise.
  #
  #     # this check is inside add_block! method.
  #     if options[:allow_font_face] && !(block !~ RE_AT_FONTFACE_RULE)
  #      block.gsub!(/\n/, "")
  #     end
  # !(block !~ RE_AT_FONTFACE_RULE) will return true if font-face exists.

  def test_allowing_font_face_rule

    css_block = "@font-face {
      src: url('https://test.css.net/1') format('f1'),
      url('https://test.css.net/2') format('f2');
      }"

    parser = Parser.new
    parser.add_block!(css_block, :allow_font_face => true)

    assert_equal false, css_block.include?("\n")
  end

  def test_not_allowing_font_face_rule

    css_block = "@font-face {
      src: url('https://test.css.net/1') format('f1'),
      url('https://test.css.net/2') format('f2');
      }"

    parser = Parser.new
    parser.add_block!(css_block, :allow_font_face => false)

    assert_equal true, css_block.include?("\n")
  end

  def test_following_badly_escaped_import_rules
    css_block = '@import "http://example.com/css?family=Droid+Sans:regular,bold|Droid+Serif:regular,italic,bold,bolditalic&subset=latin";'

    assert_raises CssParser::RemoteFileError do
      @cp.add_block!(css_block, :base_uri => "#{@uri_base}/subdir/")
    end
  end

  def test_loading_malformed_content_strings
    file_name = File.dirname(__FILE__) + '/fixtures/import-malformed.css'
    @cp.load_file!(file_name)
    @cp.each_selector do |sel, dec, spec|
      assert_nil dec =~ /wellformed/
    end
  end

  def test_loading_malformed_css_brackets
    file_name = File.dirname(__FILE__) + '/fixtures/import-malformed.css'
    @cp.load_file!(file_name)
    selector_count = 0
    @cp.each_selector do |sel, dec, spec|
      selector_count += 1
    end

    assert_equal 8, selector_count
  end

  def test_following_at_import_rules_from_add_block
    css_block = '@import "../simple.css";'

    @cp.add_block!(css_block, :base_uri => "#{@uri_base}/subdir/")

    # from 'simple.css'
    assert_equal 'margin: 0px;', @cp.find_by_selector('p').join(' ')
  end

  def test_importing_with_media_types
    @cp.load_uri!("#{@uri_base}/import-with-media-types.css")

    # from simple.css with :screen media type
    assert_equal 'margin: 0px;', @cp.find_by_selector('p', :screen).join(' ')
    assert_equal '', @cp.find_by_selector('p', :tty).join(' ')
  end

  def test_local_circular_reference_exception
    assert_raises CircularReferenceError do
      @cp.load_file!(File.dirname(__FILE__) + '/fixtures/import-circular-reference.css')
    end
  end

  def test_remote_circular_reference_exception
    assert_raises CircularReferenceError do
      @cp.load_uri!("#{@uri_base}/import-circular-reference.css")
    end
  end

  def test_suppressing_circular_reference_exceptions
    cp_without_exceptions = Parser.new(:io_exceptions => false)

    cp_without_exceptions.load_uri!("#{@uri_base}/import-circular-reference.css")
  end

  def test_toggling_not_found_exceptions
    cp_with_exceptions = Parser.new(:io_exceptions => true)

    assert_raises RemoteFileError do
      cp_with_exceptions.load_uri!("#{@uri_base}/no-exist.xyz")
    end

    cp_without_exceptions = Parser.new(:io_exceptions => false)

    cp_without_exceptions.load_uri!("#{@uri_base}/no-exist.xyz")
  end
end
