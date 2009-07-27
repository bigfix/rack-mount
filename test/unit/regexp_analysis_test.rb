require 'test_helper'

class RegexpAnalysisTest < Test::Unit::TestCase
  DynamicSegment = Rack::Mount::Generation::Route::DynamicSegment
  Capture = Rack::Mount::Utils::Capture
  EOS = Rack::Mount::Const::NULL

  def test_requires_match_start_of_string
    re = %r{/foo$}
    assert_equal [], extract_static_segments(re)
    assert_equal [], build_generation_segments(re)
    assert_raise(ArgumentError) { extract_regexp_parts(re) }
  end

  def test_simple_static_string
    re = parse_segmented_string('/foo', {}, %w( / . ? ))

    assert_equal %r{\A/foo\Z}, re
    assert_equal ['foo', EOS], extract_static_segments(re)
    assert_equal ['/foo'], build_generation_segments(re)
    assert_equal ['/foo', EOS], extract_regexp_parts(re)
  end

  def test_root_path
    re = parse_segmented_string('/', {}, %w( / . ? ))

    assert_equal %r{\A/\Z}, re
    assert_equal [EOS], extract_static_segments(re)
    assert_equal ['/'], build_generation_segments(re)
    assert_equal ['/', EOS], extract_regexp_parts(re)
  end

  def test_multisegment_static_string
    re = parse_segmented_string('/people/show/1', {}, %w( / . ? ))

    assert_equal %r{\A/people/show/1\Z}, re
    assert_equal ['people', 'show', '1', EOS], extract_static_segments(re)
    assert_equal ['/people/show/1'], build_generation_segments(re)
    assert_equal ['/people/show/1', EOS], extract_regexp_parts(re)
  end

  def test_dynamic_segments
    re = parse_segmented_string('/foo/:action/:id', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/foo/(?<action>[^/.?]+)/(?<id>[^/.?]+)\Z}'), re
    else
      assert_equal %r{\A/foo/([^/.?]+)/([^/.?]+)\Z}, re
    end

    assert_equal ['foo', %r{\A[^/.?]+\Z}, %r{\A[^/.?]+\Z}, EOS], extract_static_segments(re)
    assert_equal ['/foo/', DynamicSegment.new(:action, %r{[^/.?]+}), '/', DynamicSegment.new(:id, %r{[^/.?]+})], build_generation_segments(re)
    assert_equal [
      '/foo/', Capture.new('[^/.?]+', :name => 'action'),
      '/', Capture.new('[^/.?]+', :name => 'id'), EOS
    ], extract_regexp_parts(re)
  end

  def test_dynamic_segments_with_requirements
    re = parse_segmented_string('/foo/:action/:id',
      { :action => /bar|baz/, :id => /[a-z0-9]+/ }, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/foo/(?<action>bar|baz)/(?<id>[a-z0-9]+)\Z}'), re
    else
      assert_equal %r{\A/foo/(bar|baz)/([a-z0-9]+)\Z}, re
    end

    assert_equal ['foo', %r{\Abar|baz\Z}, %r{\A[a-z0-9]+\Z}, EOS], extract_static_segments(re)
    assert_equal ['/foo/', DynamicSegment.new(:action, %r{bar|baz}), '/', DynamicSegment.new(:id, %r{[a-z0-9]+})], build_generation_segments(re)
    assert_equal [
      '/foo/', Capture.new('bar|baz', :name => 'action'),
      '/', Capture.new('[a-z0-9]+', :name => 'id'), EOS
    ], extract_regexp_parts(re)
  end

  def test_requirements_with_capture_inside
    re = parse_segmented_string('/msg/get/:id', { :id => /\d+(?:,\d+)*/ }, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/msg/get/(?<id>\d+(?:,\d+)*)\Z}'), re
    else
      assert_equal %r{\A/msg/get/(\d+(?:,\d+)*)\Z}, re
    end
    assert_equal ['msg', 'get', %r{\A\d+(?:,\d+)*\Z}, EOS], extract_static_segments(re)
    assert_equal ['/msg/get/',
      DynamicSegment.new(:id, %r{\d+(?:,\d+)*})
    ], build_generation_segments(re)
    assert_equal ['/msg/get/',
      Capture.new('\\d+', Capture.new('?:,\\d+'), '*', :name => 'id'), EOS
    ], extract_regexp_parts(re)
  end

  def test_optional_capture
    re = parse_segmented_string('/people/(:id)', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/people/((?<id>[^/.?]+))?\Z}'), re
    else
      assert_equal %r{\A/people/(([^/.?]+))?\Z}, re
    end

    assert_equal ['people'], extract_static_segments(re)
    assert_equal ['/people/', [DynamicSegment.new(:id, %r{[^/.?]+})]], build_generation_segments(re)
    assert_equal ['/people/', Capture.new(
      Capture.new('[^/.?]+', :name => 'id'),
    :optional => true), EOS], extract_regexp_parts(re)
  end

  def test_escaped_optional_capture
    re = parse_segmented_string('/foo/\(bar', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/foo/\(bar\Z}'), re
    else
      assert_equal %r{\A/foo/\(bar\Z}, re
    end

    assert_equal ['foo', '(bar', EOS], extract_static_segments(re)
    assert_equal ['/foo/(bar'], build_generation_segments(re)
    assert_equal ['/foo/\\(bar', EOS], extract_regexp_parts(re)
  end

  def test_leading_dynamic_segment
    re = parse_segmented_string('/:foo/bar(.:format)', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/(?<foo>[^/.?]+)/bar(\.(?<format>[^/.?]+))?\Z}'), re
    else
      assert_equal %r{\A/([^/.?]+)/bar(\.([^/.?]+))?\Z}, re
    end

    assert_equal [%r{\A[^/.?]+\Z}, 'bar'], extract_static_segments(re)
    assert_equal ['/', DynamicSegment.new(:foo, %r{[^/.?]+}),
      '/bar', ['.', DynamicSegment.new(:format, %r{[^/.?]+})]], build_generation_segments(re)
    assert_equal ['/', Capture.new('[^/.?]+', :name => 'foo'), '/bar',
      Capture.new('\\.', Capture.new('[^/.?]+', :name => 'format'), :optional => true),
    EOS], extract_regexp_parts(re)
  end

  def test_optional_capture_within_segment
    re = parse_segmented_string('/people(.:format)', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/people(\\.(?<format>[^/.?]+))?\Z}'), re
    else
      assert_equal %r{\A/people(\.([^/.?]+))?\Z}, re
    end

    assert_equal ['people'], extract_static_segments(re)
    assert_equal ['/people', ['.', DynamicSegment.new(:format, %r{[^/.?]+})]], build_generation_segments(re)
    assert_equal ['/people', Capture.new('\\.',
      Capture.new('[^/.?]+', :name => 'format'),
    :optional => true), EOS], extract_regexp_parts(re)
  end

  def test_dynamic_and_optional_segment
    re = parse_segmented_string('/people/:id(.:format)', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/people/(?<id>[^/.?]+)(\\.(?<format>[^/.?]+))?\Z}'), re
    else
      assert_equal %r{\A/people/([^/.?]+)(\.([^/.?]+))?\Z}, re
    end

    assert_equal ['people', %r{\A[^/.?]+\Z}], extract_static_segments(re)
    assert_equal ['/people/', DynamicSegment.new(:id, %r{[^/.?]+}), ['.', DynamicSegment.new(:format, %r{[^/.?]+})]], build_generation_segments(re)
    assert_equal ['/people/', Capture.new('[^/.?]+', :name => 'id'), ['\\.', Capture.new('[^/.?]+', :name => 'format')], EOS], extract_regexp_parts(re)
  end

  def test_multiple_optional_captures
    re = parse_segmented_string('/:foo(/:bar)(/:baz)', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/(?<foo>[^/.?]+)(/(?<bar>[^/.?]+))?(/(?<baz>[^/.?]+))?\Z}'), re
    else
      assert_equal %r{\A/([^/.?]+)(/([^/.?]+))?(/([^/.?]+))?\Z}, re
    end

    assert_equal [%r{\A[^/.?]+\Z}], extract_static_segments(re)
    assert_equal ['/', DynamicSegment.new(:foo, %r{[^/.?]+}),
      ['/', DynamicSegment.new(:bar, %r{[^/.?]+})],
      ['/', DynamicSegment.new(:baz, %r{[^/.?]+})]
    ], build_generation_segments(re)
    assert_equal ['/', Capture.new('[^/.?]+', :name => 'foo'),
      Capture.new('/', Capture.new('[^/.?]+', :name => 'bar'), :optional => true),
      Capture.new('/', Capture.new('[^/.?]+', :name => 'baz'), :optional => true), EOS
    ], extract_regexp_parts(re)
  end

  def test_nested_optional_captures
    re = parse_segmented_string('/:controller(/:action(/:id(.:format)))', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/(?<controller>[^/.?]+)(/(?<action>[^/.?]+)(/(?<id>[^/.?]+)(\\.(?<format>[^/.?]+))?)?)?\Z}'), re
    else
      assert_equal %r{\A/([^/.?]+)(/([^/.?]+)(/([^/.?]+)(\.([^/.?]+))?)?)?\Z}, re
    end

    assert_equal [%r{\A[^/.?]+\Z}], extract_static_segments(re)
    assert_equal ['/', DynamicSegment.new(:controller, %r{[^/.?]+}), ['/', DynamicSegment.new(:action, %r{[^/.?]+}), ['/', DynamicSegment.new(:id, %r{[^/.?]+}), ['.', DynamicSegment.new(:format, %r{[^/.?]+})]]]], build_generation_segments(re)
    assert_equal ['/', Capture.new('[^/.?]+', :name => 'controller'),
      Capture.new('/', Capture.new('[^/.?]+', :name => 'action'),
        Capture.new('/', Capture.new('[^/.?]+', :name => 'id'),
          Capture.new('\\.', Capture.new('[^/.?]+', :name => 'format'), :optional => true),
        :optional => true),
      :optional => true), EOS
    ], extract_regexp_parts(re)
  end

  def test_regexp_simple_requirements
    re = %r{^/foo/(bar|baz)/([a-z0-9]+)$}

    assert_equal ['foo', %r{\Abar|baz\Z}, %r{\A[a-z0-9]+\Z}, EOS], extract_static_segments(re)
    assert_equal [], build_generation_segments(re)
    assert_equal ['/foo/', Capture.new('bar|baz'), '/',
      Capture.new('[a-z0-9]+'), EOS], extract_regexp_parts(re)
  end

  def test_another_regexp_with_requirements
    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      re = eval('%r{\A/regexp/bar/(?<action>[a-z]+)/(?<id>[0-9]+)\Z}')
      re = Rack::Mount::RegexpWithNamedGroups.new(re)
    else
      re = Rack::Mount::RegexpWithNamedGroups.new(%r{\A/regexp/bar/(?:<action>[a-z]+)/(?:<id>[0-9]+)\Z})
    end

    assert_equal ['regexp', 'bar', /\A[a-z]+\Z/, /\A[0-9]+\Z/, EOS], extract_static_segments(re)
    assert_equal ['/regexp/bar/', DynamicSegment.new(:action, /[a-z]+/), '/', DynamicSegment.new(:id, /[0-9]+/)], build_generation_segments(re)
    assert_equal ['/regexp/bar/', Capture.new('[a-z]+', :name => 'action'),
      '/', Capture.new('[0-9]+', :name => 'id'), EOS], extract_regexp_parts(re)
  end

  def test_period_separator
    re = parse_segmented_string('/foo/:id.:format', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/foo/(?<id>[^/.?]+)\\.(?<format>[^/.?]+)\Z}'), re
    else
      assert_equal %r{\A/foo/([^/.?]+)\.([^/.?]+)\Z}, re
    end

    assert_equal ['foo', %r{\A[^/.?]+\Z}, %r{\A[^/.?]+\Z}, EOS], extract_static_segments(re)
    assert_equal ['/foo/', DynamicSegment.new(:id, %r{[^/.?]+}), '.', DynamicSegment.new(:format, %r{[^/.?]+})], build_generation_segments(re)
    assert_equal ['/foo/', Capture.new('[^/.?]+', :name => 'id'),
      '\\.', Capture.new('[^/.?]+', :name => 'format'), EOS
    ], extract_regexp_parts(re)
  end

  def test_glob
    re = parse_segmented_string('/files/*files', {}, %w( / . ? ))

    if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
      assert_equal eval('%r{\A/files/(?<files>.+)\Z}'), re
    else
      assert_equal %r{\A/files/(.+)\Z}, re
    end

    assert_equal ['files'], extract_static_segments(re)
    assert_equal ['/files/', DynamicSegment.new(:files, /.+/)], build_generation_segments(re)
    assert_equal ['/files/', Capture.new('.+', :name => 'files'), EOS],
      extract_regexp_parts(re)
  end

  def test_prefix_regexp
    re = %r{^/prefix}
    assert_equal ['prefix'], extract_static_segments(re)
    assert_equal ['/prefix'], build_generation_segments(re)
    assert_equal ['/prefix'], extract_regexp_parts(re)
  end

  if Rack::Mount::Const::SUPPORTS_NAMED_CAPTURES
    def test_named_regexp_groups
      re = eval('%r{^/(?<controller>[a-z0-9]+)/(?<action>[a-z0-9]+)/(?<id>[0-9]+)$}')

      assert_equal [%r{\A[a-z0-9]+\Z}, %r{\A[a-z0-9]+\Z}, %r{\A[0-9]+\Z}, EOS], extract_static_segments(re)
      assert_equal ['/', DynamicSegment.new(:controller, %r{[a-z0-9]+}), '/', DynamicSegment.new(:action, %r{[a-z0-9]+}), '/', DynamicSegment.new(:id, %r{[0-9]+})], build_generation_segments(re)
      assert_equal ['/', Capture.new('[a-z0-9]+', :name => 'controller'),
        '/', Capture.new('[a-z0-9]+', :name => 'action'),
        '/', Capture.new('[0-9]+', :name => 'id'), EOS
      ], extract_regexp_parts(re)
    end

    def test_leading_static_segment
      re = eval('%r{^/ruby19/(?<action>[a-z]+)/(?<id>[0-9]+)$}')

      assert_equal ['ruby19', %r{\A[a-z]+\Z}, %r{\A[0-9]+\Z}, EOS], extract_static_segments(re)
      assert_equal ['/ruby19/', DynamicSegment.new(:action, %r{[a-z]+}), '/', DynamicSegment.new(:id, %r{[0-9]+})], build_generation_segments(re)
      assert_equal ['/ruby19/', Capture.new('[a-z]+', :name => 'action'),
        '/', Capture.new('[0-9]+', :name => 'id'), EOS
      ], extract_regexp_parts(re)
    end
  end

  private
    def parse_segmented_string(*args)
      Rack::Mount::RegexpWithNamedGroups.new(Rack::Mount::Strexp.new(*args))
    end

    def extract_regexp_parts(*args)
      Rack::Mount::Utils.extract_regexp_parts(*args)
    end

    def extract_static_segments(re)
      set = Rack::Mount::RouteSet.new
      route = Rack::Mount::Route.new(set, EchoApp, { :path_info => re }, {}, nil)
      route.conditions[:path_info].keys.sort { |(k1, v1), (k2, v2)| k1.to_s <=> k2.to_s }.map { |(k, v)| v }
    end

    def build_generation_segments(re)
      set = Rack::Mount::RouteSet.new
      route = Rack::Mount::Route.new(set, EchoApp, { :path_info => re }, {}, nil)
      route.instance_variable_get('@segments')[:path_info]
    end
end
