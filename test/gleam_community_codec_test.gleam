import gleeunit
import gleeunit/should
import gleam_community/codec
import gleam/io

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
    codec.custom3(fn(foo, bar, baz, value) {
      case value {
        Foo -> foo
        Bar(s) -> bar(s)
        Baz(s, i) -> baz(s, i)
      }
    })
    |> codec.variant0("Foo", Foo)
    |> codec.variant1("Bar", Bar, codec.string())
    |> codec.variant2("Baz", Baz, codec.string(), codec.int())
    |> codec.construct

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
