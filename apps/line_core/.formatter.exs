# Used by "mix format"
[
  # Without these the formatter does not know Ecto's schema/migration macros
  # take no parens, and rewrites `field :name, :string` into `field(...)`.
  import_deps: [:ecto, :ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
