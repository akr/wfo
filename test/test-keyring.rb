require 'test/unit'
require 'keyring'

class TestKeyRing < Test::Unit::TestCase
  def assert_decode_strings(expected, test)
    assert_equal(expected, KeyRing.decode_strings(test), test.inspect)
    assert_equal(expected, KeyRing.decode_strings_safe(test), test.inspect)
  end

  def assert_decode_strings_raises(test)
    assert_raises(ArgumentError, test.inspect) { KeyRing.decode_strings(test) }
    assert_raises(ArgumentError, test.inspect) { KeyRing.decode_strings_safe(test) }
  end

  def test_decode_strings
    assert_decode_strings([], "")
    assert_decode_strings([], " ")
    assert_decode_strings([], "\n")
    assert_decode_strings(%w[a], 'a')
    assert_decode_strings(%w[a b c], 'a b c')
    assert_decode_strings(%w[a b c], 'a "b" c')
    assert_decode_strings(["a", "\" \\ \t", "c"], 'a "\" \\\\ \x09" c')
    assert_decode_strings_raises('"')
    assert_decode_strings_raises('"a"b')
  end
end
