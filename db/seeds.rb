# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

instances = [
  ["twitter.com", "twitter"],
  ["facebook.com", "facebook"],
  ["www.facebook.com", "facebook"],
  ["line.me", "line"],
  ["line", "line"],
  ["b.hatena.ne.jp", "hatenabookmark"],
  ["getpocket.com", "pocket"],
  ["pocket", "pocket"],
  ["linkedin.com", "linkedin"],
  ["www.linkedin.com", "linkedin"],
  ["pinterest.com", "pinterest"],
  ["www.pinterest.com", "pinterest"],
  ["pinterest.jp", "pinterest"],
  ["www.pinterest.jp", "pinterest"],
  ["www.xing.com", "xing"],
]

instances.each do |name, type|
  Instance.create(name: name, instance_type: type, version: "", permanent: true)
end
