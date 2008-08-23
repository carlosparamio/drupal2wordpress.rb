require "rubygems"
gem     "activerecord"
require "active_record"

module Drupal
  ADAPTER    = "mysql"
  HOST       = "example.drupal.hostname"
  USERNAME   = "username"
  PASSWORD   = "password"
  DATABASE   = "database"
  GMT_OFFSET = -2.hours
  
  def connection
    establish_connection(
      :adapter  => Drupal::ADAPTER,
      :host     => Drupal::HOST,
      :username => Drupal::USERNAME,
      :password => Drupal::PASSWORD,
      :database => Drupal::DATABASE
    )
  end
  
  class Category < ActiveRecord::Base
    Drupal.connection
    set_table_name :term_data
    set_primary_key :tid
  end

  class Post < ActiveRecord::Base
    Drupal.connection
    set_table_name :node_revisions
    set_primary_key :vid
  end

  class PostCategory < ActiveRecord::Base
    Drupal.connection
    set_table_name :term_node
  end

  class Comment < ActiveRecord::Base
    Drupal.connection
    set_table_name :comments
    set_primary_key :cid
  end

  class Node < ActiveRecord::Base
    Drupal.connection
    set_table_name :node
    set_primary_key :nid
    self.inheritance_column = "type_not_used" # ActiveRecord tries to use type for polymorphic
  end

  class URL < ActiveRecord::Base
    Drupal.connection
    set_table_name :url_alias
    set_primary_key :pid
  end
  
end

module WordPress
  ADAPTER  = "mysql"
  HOST     = "example.wordpress.hostname"
  USERNAME = "username"
  PASSWORD = "password"
  DATABASE = "database"
  POST_URL = "http://example.wordpress.hostname/?p=%s"
  
  def connection
    establish_connection(
      :adapter  => WordPress::ADAPTER,
      :host     => WordPress::HOST,
      :username => WordPress::USERNAME,
      :password => WordPress::PASSWORD,
      :database => WordPress::DATABASE
    )
  end
  
  class Category < ActiveRecord::Base
    WordPress.connection
    set_table_name :wp_terms
    set_primary_key :term_id
  end

  class Taxonomy < ActiveRecord::Base
    WordPress.connection
    set_table_name :wp_term_taxonomy
    set_primary_key :term_taxonomy_id
  end

  class Post < ActiveRecord::Base
    WordPress.connection
    set_table_name :wp_posts
    set_primary_key :ID
  end

  class Comment < ActiveRecord::Base
    WordPress.connection
    set_table_name :wp_comments
    set_primary_key :comment_ID
  end

  class PostCategory < ActiveRecord::Base
    WordPress.connection
    set_table_name :wp_term_relationships
    set_primary_key nil
  end
end

# Remember equivalent WordPress category records
@drupal_category_ids_to_wordpress_category_ids = {}

drupal_categories = Drupal::Category.find(:all)
drupal_categories.each do |drupal_category|
  wordpress_category = WordPress::Category.new
  wordpress_category.name = drupal_category.name
  wordpress_category.slug = drupal_category.name.downcase.gsub(" ", "-")
  wordpress_category.save!

  wordpress_taxonomy = WordPress::Taxonomy.new
  wordpress_taxonomy.term_id     = wordpress_category.term_id
  wordpress_taxonomy.description = drupal_category.description
  wordpress_taxonomy.taxonomy    = "category"
  wordpress_taxonomy.save!
  @drupal_category_ids_to_wordpress_category_ids[drupal_category.tid] = wordpress_category.term_id
end

# Remember equivalent WordPress post records
@drupal_post_ids_to_wordpress_post_ids = {}

drupal_posts = Drupal::Post.find(:all)
drupal_posts.each do |drupal_post|
  wordpress_post                       = WordPress::Post.new
  wordpress_post.post_author           = 1 # FIXME Hardcoded author
  wordpress_post.post_title            = drupal_post.title
  wordpress_post.post_content          = drupal_post.body.gsub("<!--break-->", "<!--more-->")
  wordpress_post.post_date             = Time.at(drupal_post.timestamp)
  wordpress_post.post_date_gmt         = wordpress_post.post_date + Drupal::GMT_OFFSET
  wordpress_post.post_category         = 0
  wordpress_post.post_excerpt          = ""
  wordpress_post.comment_status        = "open"
  wordpress_post.post_modified         = wordpress_post.post_date
  wordpress_post.post_modified_gmt     = wordpress_post.post_date_gmt
  wordpress_post.post_type             = "post"
  wordpress_post.guid                  = WordPress::POST_URL % wordpress_post.ID
  wordpress_post.post_name             = Drupal::URL.find(:first, :conditions => ["src LIKE 'node/?'", drupal_post.nid]).dst.gsub("blog/", "") rescue ""
  wordpress_post.menu_order            = 0
  wordpress_post.comment_count         = Drupal::Comment.count(:conditions => ["nid = ?", drupal_post.nid])
  wordpress_post.post_mime_type        = ""
  wordpress_post.post_content_filtered = ""
  wordpress_post.post_password         = ""
  wordpress_post.post_parent           = 0
  wordpress_post.ping_status           = "open"
  wordpress_post.post_status           = Drupal::Node.find(:first, :conditions => ["nid = ?", drupal_post.nid]).status == 1 ? "publish" : "draft"
  wordpress_post.pinged                = ""
  wordpress_post.to_ping               = ""
  wordpress_post.save!
  @drupal_post_ids_to_wordpress_post_ids[drupal_post.nid] = wordpress_post.ID
end

drupal_comments = Drupal::Comment.find(:all)
drupal_comments.each do |drupal_comment|
  wordpress_comment = WordPress::Comment.new
  wordpress_comment.comment_date         = Time.at(drupal_comment.timestamp)
  wordpress_comment.comment_date_gmt     = wordpress_comment.comment_date + Drupal::GMT_OFFSET
  wordpress_comment.comment_approved     = drupal_comment.status == 0 ? 1 : 0
  wordpress_comment.comment_parent       = 0
  wordpress_comment.comment_content      = drupal_comment.comment
  wordpress_comment.comment_post_ID      = @drupal_post_ids_to_wordpress_post_ids[drupal_comment.nid]
  wordpress_comment.comment_author       = drupal_comment.name
  wordpress_comment.comment_agent        = ""
  wordpress_comment.user_id              = drupal_comment.uid
  wordpress_comment.comment_type         = ""
  wordpress_comment.comment_author_email = drupal_comment.mail
  wordpress_comment.comment_karma        = 0
  wordpress_comment.comment_author_url   = drupal_comment.homepage
  wordpress_comment.comment_author_IP    = drupal_comment.hostname
  wordpress_comment.save!
end

drupal_posts_categories = Drupal::PostCategory.find(:all)
drupal_posts_categories.each do |drupal_post_category|
  wordpress_post_category = WordPress::PostCategory.new
  wordpress_post_category.term_taxonomy_id = WordPress::Taxonomy.find_by_term_id(@drupal_category_ids_to_wordpress_category_ids[drupal_post_category.tid]).term_taxonomy_id
  wordpress_post_category.object_id = @drupal_post_ids_to_wordpress_post_ids[drupal_post_category.nid]
  wordpress_post_category.save!
end