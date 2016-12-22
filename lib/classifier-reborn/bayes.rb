# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

require_relative 'category_namer'
require_relative 'backends/bayes_memory_backend'
require_relative 'backends/bayes_redis_backend'

module ClassifierReborn
  class Bayes
    CategoryNotFoundError = Class.new(StandardError)

    # The class can be created with one or more categories, each of which will be
    # initialized and given a training method. E.g.,
    #      b = ClassifierReborn::Bayes.new 'Interesting', 'Uninteresting', 'Spam'
    #
    # Options available are:
    #   language:         'en'   Used to select language specific stop words
    #   auto_categorize:  false  When true, enables ability to dynamically declare a category
    #   enable_threshold: false  When true, enables a threshold requirement for classifition
    #   threshold:        0.0    Default threshold, only used when enabled
    #   enable_stemmer:   true   When false, disables word stemming
    def initialize(*args)
      initial_categories = []
      options = { language:         'en',
                  auto_categorize:  false,
                  enable_threshold: false,
                  threshold:        0.0,
                  enable_stemmer:   true,
                  redis_con_str:    ''
                }
      args.flatten.each do |arg|
        if arg.is_a?(Hash)
          options.merge!(arg)
        else
          initial_categories.push(arg)
        end
      end

      @backend = options[:redis_con_str].empty? ? BayesMemoryBackend.new : BayesRedisBackend.new(options[:redis_con_str])

      initial_categories.each do |c|
        add_category(c)
      end

      @language            = options[:language]
      @auto_categorize     = options[:auto_categorize]
      @enable_threshold    = options[:enable_threshold]
      @threshold           = options[:threshold]
      @enable_stemmer      = options[:enable_stemmer]
    end

    # Provides a general training method for all categories specified in Bayes#new
    # For example:
    #     b = ClassifierReborn::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.train "that", "That text"
    #     b.train "The other", "The other text"
    def train(category, text)
      category = CategoryNamer.prepare_name(category)

      # Add the category dynamically or raise an error
      unless category_keys.include?(category)
        if @auto_categorize
          add_category(category)
        else
          raise CategoryNotFoundError, "Cannot train; category #{category} does not exist"
        end
      end

      @backend.update_category_training_count(category, 1)
      @backend.update_total_trainings(1)
      Hasher.word_hash(text, @language, @enable_stemmer).each do |word, count|
        @backend.update_category_word_frequency(category, word, count)
        @backend.update_category_word_count(category, count)
        @backend.update_total_words(count)
      end
    end

    # Provides a untraining method for all categories specified in Bayes#new
    # Be very careful with this method.
    #
    # For example:
    #     b = ClassifierReborn::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.untrain :this, "This text"
    def untrain(category, text)
      category = CategoryNamer.prepare_name(category)
      @backend.update_category_training_count(category, -1)
      @backend.update_total_trainings(-1)
      Hasher.word_hash(text, @language, @enable_stemmer).each do |word, count|
        next if @backend.total_words < 0
        orig = @backend.category_word_frequency(category, word) || 0
        @backend.update_category_word_frequency(category, word, -count)
        if @backend.category_word_frequency(category, word) <= 0
          @backend.delete_category_word(category, word)
          count = orig
        end

        @backend.update_category_word_count(category, -count) if @backend.category_word_count(category) >= count
        @backend.update_total_words(-count)
      end
    end

    # Returns the scores in each category the provided +text+. E.g.,
    #    b.classifications "I hate bad words and you"
    #    =>  {"Uninteresting"=>-12.6997928013932, "Interesting"=>-18.4206807439524}
    # The largest of these scores (the one closest to 0) is the one picked out by #classify
    def classifications(text)
      score = {}
      word_hash = Hasher.word_hash(text, @language, @enable_stemmer)
      category_keys.each do |category|
        score[category.to_s] = 0
        total = (@backend.category_word_count(category) || 1).to_f
        word_hash.each do |word, _count|
          s = @backend.word_in_category?(category, word) ? @backend.category_word_frequency(category, word) : 0.1
          score[category.to_s] += Math.log(s / total)
        end
        # now add prior probability for the category
        s = @backend.category_has_trainings?(category) ? @backend.category_training_count(category) : 0.1
        score[category.to_s] += Math.log(s / @backend.total_trainings.to_f)
      end
      score
    end

    # Returns the classification of the provided +text+, which is one of the
    # categories given in the initializer along with the score. E.g.,
    #    b.classify "I hate bad words and you"
    #    =>  ['Uninteresting', -4.852030263919617]
    def classify_with_score(text)
      (classifications(text).sort_by { |a| -a[1] })[0]
    end

    # Return the classification without the score
    def classify(text)
      result, score = classify_with_score(text)
      result = nil if score < @threshold || score == Float::INFINITY if threshold_enabled?
      result
    end

    # Retrieve the current threshold value
    attr_reader :threshold

    # Dynamically set the threshold value
    attr_writer :threshold

    # Dynamically enable threshold for classify results
    def enable_threshold
      @enable_threshold = true
    end

    # Dynamically disable threshold for classify results
    def disable_threshold
      @enable_threshold = false
    end

    # Is threshold processing enabled?
    def threshold_enabled?
      @enable_threshold
    end

    # is threshold processing disabled?
    def threshold_disabled?
      !@enable_threshold
    end

    # Is word stemming enabled?
    def stemmer_enabled?
      @enable_stemmer
    end

    # Is word stemming disabled?
    def stemmer_disabled?
      !@enable_stemmer
    end

    # Provides training and untraining methods for the categories specified in Bayes#new
    # For example:
    #     b = ClassifierReborn::Bayes.new 'This', 'That', 'the_other'
    #     b.train_this "This text"
    #     b.train_that "That text"
    #     b.untrain_that "That text"
    #     b.train_the_other "The other text"
    def method_missing(name, *args)
      cleaned_name = name.to_s.gsub(/(un)?train_([\w]+)/, '\2')
      category = CategoryNamer.prepare_name(cleaned_name)
      if category_keys.include?(category)
        args.each { |text| eval("#{Regexp.last_match(1)}train(category, text)") }
      elsif name.to_s =~ /(un)?train_([\w]+)/
        raise StandardError, "No such category: #{category}"
      else
        super # raise StandardError, "No such method: #{name}"
      end
    end

    # Provides a list of category names
    # For example:
    #     b.categories
    #     =>   ['This', 'That', 'the_other']
    def categories # :nodoc:
      category_keys.collect(&:to_s)
    end

    def category_keys
      @backend.category_keys
    end

    # Allows you to add categories to the classifier.
    # For example:
    #     b.add_category "Not spam"
    #
    # WARNING: Adding categories to a trained classifier will
    # result in an undertrained category that will tend to match
    # more criteria than the trained selective categories. In short,
    # try to initialize your categories at initialization.
    def add_category(category)
      category = CategoryNamer.prepare_name(category)
      @backend.add_category(category)
    end

    alias_method :append_category, :add_category
  end
end
