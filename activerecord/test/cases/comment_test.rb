require 'cases/helper'
require 'support/schema_dumping_helper'

class CommentTest < ActiveRecord::TestCase
  include SchemaDumpingHelper
  self.use_transactional_tests = false if current_adapter?(:Mysql2Adapter)

  class Commented < ActiveRecord::Base
    self.table_name = 'commenteds'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    @connection.transaction do
      @connection.create_table('commenteds', comment: 'A table with comment', force: true) do |t|
        t.string  'name',    comment: 'Comment should help clarify the column purpose'
        t.boolean 'obvious', comment: 'Question is: should you comment obviously named objects?'
        t.string  'content'
        t.index   'name',    comment: %Q["Very important" index that powers all the performance.\nAnd it's fun!]
      end
    end
  end

  teardown do
    @connection.drop_table 'commenteds', if_exists: true
  end

  if current_adapter?(:Mysql2Adapter, :PostgreSQLAdapter)

    def test_column_created_in_block
      Commented.reset_column_information
      column = Commented.columns_hash['name']
      assert_equal :string, column.type
      assert_equal 'Comment should help clarify the column purpose', column.comment
    end

    def test_add_column_with_comment_later
      @connection.add_column :commenteds, :rating, :integer, comment: 'I am running out of imagination'
      Commented.reset_column_information
      column = Commented.columns_hash['rating']

      assert_equal :integer, column.type
      assert_equal 'I am running out of imagination', column.comment
    end

    def test_add_index_with_comment_later
      @connection.add_index :commenteds, :obvious, name: 'idx_obvious', comment: 'We need to see obvious comments'
      index = @connection.indexes('commenteds').find { |idef| idef.name == 'idx_obvious' }
      assert_equal 'We need to see obvious comments', index.comment
    end

    def test_add_comment_to_column
      @connection.change_column :commenteds, :content, :string, comment: 'Whoa, content describes itself!'

      Commented.reset_column_information
      column = Commented.columns_hash['content']

      assert_equal :string, column.type
      assert_equal 'Whoa, content describes itself!', column.comment
    end

    def test_remove_comment_from_column
      @connection.change_column :commenteds, :obvious, :string, comment: nil

      Commented.reset_column_information
      column = Commented.columns_hash['obvious']

      assert_equal :string, column.type
      assert_nil column.comment
    end

    def test_schema_dump_with_comments
      # Do all the stuff from other tests
      @connection.add_column    :commenteds, :rating, :integer, comment: 'I am running out of imagination'
      @connection.change_column :commenteds, :content, :string, comment: 'Whoa, content describes itself!'
      @connection.change_column :commenteds, :obvious, :string, comment: nil
      @connection.add_index     :commenteds, :obvious, name: 'idx_obvious', comment: 'We need to see obvious comments'
      # And check that these changes are reflected in dump
      output = dump_table_schema 'commenteds'
      assert_match %r[create_table "commenteds",.+\s+comment: "A table with comment"], output
      assert_match %r[t\.string\s+"name",\s+comment: "Comment should help clarify the column purpose"], output
      assert_match %r[t\.string\s+"obvious"\n], output
      assert_match %r[t\.string\s+"content",\s+comment: "Whoa, content describes itself!"], output
      assert_match %r[t\.integer\s+"rating",\s+comment: "I am running out of imagination"], output
      assert_match %r[add_index\s+.+\s+comment: "\\\"Very important\\\" index that powers all the performance.\\nAnd it's fun!"], output
      assert_match %r[add_index\s+.+\s+name: "idx_obvious",.+\s+comment: "We need to see obvious comments"], output
    end

  end
end
