# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

instances = [
  ["twitter.com", "twitter"],
  ["x.com", "twitter"],
  ["facebook.com", "facebook"],
  ["www.facebook.com", "facebook"],
  ["line.me", "line"],
  ["line", "line"],
  ["b.hatena.ne.jp", "hatenabookmark"],
  ["hatena.ne.jp", "hatenabookmark"],
  ["getpocket.com", "pocket"],
  ["pocket", "pocket"],
  ["linkedin.com", "linkedin"],
  ["www.linkedin.com", "linkedin"],
  ["pinterest.com", "pinterest"],
  ["www.pinterest.com", "pinterest"],
  ["pinterest.jp", "pinterest"],
  ["www.pinterest.jp", "pinterest"],
  ["www.xing.com", "xing"],
  ["xing.com", "xing"],
  ["www.threads.net", "threads"],
  ["threads.net", "threads"],
  ["www.threads.com", "threads"],
  ["threads.com", "threads"],
  ["bsky.app", "bluesky"],
  ["bluesky", "bluesky"],
  ["www.reddit.com", "reddit"],
  ["reddit.com", "reddit"],
  ["reddit", "reddit"],
  ["www.whatsapp.com", "whatsapp"],
  ["whatsapp.com", "whatsapp"],
  ["wa.me", "whatsapp"],
  ["whatsapp", "whatsapp"],
  ["telegram.org", "telegram"],
  ["telegram", "telegram"],
]

instances.each do |name, type|
  Instance.find_or_create_by(name: name) do |instance|
    instance.instance_type = type
    instance.version = ""
    instance.permanent = true
  end
end
