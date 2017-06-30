require_relative '../test_helper'
require 'tempfile'

class HasherTest < Minitest::Test
  def setup
    @original_stopwords_path = TokenFilter::Stopword::STOPWORDS_PATH.dup
  end

  def test_word_hash
    hash = { good: 1, :'!' => 1, hope: 1, :"'" => 1, :'.' => 1, love: 1, word: 1, them: 1, test: 1 }
    assert_equal hash, Hasher.word_hash("here are some good words of test's. I hope you love them!")
  end

  def test_clean_word_hash
    hash = { good: 1, word: 1, hope: 1, love: 1, them: 1, test: 1 }
    assert_equal hash, Hasher.clean_word_hash("here are some good words of test's. I hope you love them!")
  end

  def test_clean_word_hash_without_stemming
    hash = { good: 1, words: 1, hope: 1, love: 1, them: 1, tests: 1 }
    assert_equal hash, Hasher.clean_word_hash("here are some good words of test's. I hope you love them!", 'en', false)
  end

  def test_default_stopwords
    refute_empty TokenFilter::Stopword::STOPWORDS['en']
    refute_empty TokenFilter::Stopword::STOPWORDS['fr']
    assert_empty TokenFilter::Stopword::STOPWORDS['gibberish']
  end

  def test_loads_custom_stopwords
    default_english_stopwords = TokenFilter::Stopword::STOPWORDS['en']

    # Remove the english stopwords
    TokenFilter::Stopword::STOPWORDS.delete('en')

    # Add a custom stopwords path
    TokenFilter::Stopword::STOPWORDS_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../data/stopwords')

    custom_english_stopwords = TokenFilter::Stopword::STOPWORDS['en']

    refute_equal default_english_stopwords, custom_english_stopwords
  end

  def test_add_custom_stopword_path
    # Create stopword tempfile in current directory
    temp_stopwords = Tempfile.new('xy', "#{File.dirname(__FILE__) + "/"}")

    # Add some stopwords to tempfile
    temp_stopwords << "this words fun"
    temp_stopwords.close

    # Get path of tempfile
    temp_stopwords_path = File.dirname(temp_stopwords)

    # Get tempfile name.
    temp_stopwords_name = File.basename(temp_stopwords.path)

    TokenFilter::Stopword.add_custom_stopword_path(temp_stopwords_path)
    hash = { list: 1, cool: 1 }
    assert_equal hash, Hasher.clean_word_hash("this is a list of cool words!", temp_stopwords_name)
  end

  def teardown
    TokenFilter::Stopword::STOPWORDS.clear
    TokenFilter::Stopword::STOPWORDS_PATH.clear.concat @original_stopwords_path
  end
end
