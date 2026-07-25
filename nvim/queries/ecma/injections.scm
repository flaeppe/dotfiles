; extends

; graphql-codegen and Relay mark an embedded document with a leading
; /** GraphQL */ comment instead of a gql tag. nvim-treesitter ships this
; pattern but leaves it commented out, so without this the operation is parsed
; as an ordinary template string: no GraphQL highlighting, and no function or
; parameter textobjects inside it. The gql`...`, graphql(`...`), `#graphql and
; sql`...` forms are already covered upstream.
((comment) @_gql_comment
  (#lua-match? @_gql_comment "GraphQL")
  (template_string) @injection.content
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "graphql"))
