import gleam_community/codec
import gleam/dynamic
import gleam/json
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn int_list_codec_test() {
  let int_list_codec = codec.list(codec.int())

  codec.encode_string([1, 2, 3], int_list_codec)
  |> codec.decode_string(int_list_codec)
  |> should.equal(Ok([1, 2, 3]))
}

type Example {
  Foo
  Bar(String)
  Baz(String, Int)
}

pub fn custom_type_test() {
  let example_codec =
    codec.custom({
      use foo <- codec.variant0("Foo", Foo)
      use bar <- codec.variant1("Bar", Bar, codec.string())
      use baz <- codec.variant2("Baz", Baz, codec.string(), codec.int())

      codec.make_custom(fn(value) {
        case value {
          Foo -> foo
          Bar(s) -> bar(s)
          Baz(s, i) -> baz(s, i)
        }
      })
    })

  codec.encode_string(Foo, example_codec)
  |> codec.decode_string(example_codec)
  |> should.equal(Ok(Foo))

  codec.encode_string(Bar("hello"), example_codec)
  |> codec.decode_string(example_codec)
  |> should.equal(Ok(Bar("hello")))

  codec.encode_string(Baz("hello", 42), example_codec)
  |> codec.decode_string(example_codec)
  |> should.equal(Ok(Baz("hello", 42)))
}

pub fn bool_test() {
  let bool_codec = codec.bool()

  codec.encode_string(True, bool_codec)
  |> codec.decode_string(bool_codec)
  |> should.equal(Ok(True))
}
