// IMPORTS ---------------------------------------------------------------------

import gleam/dynamic.{type DecodeError as DynamicError, DecodeError as DynamicError, type Dynamic}
import gleam/function
import gleam/json.{type DecodeError as JsonError, type Json}
import gleam/list
import gleam/map.{type Map}
import gleam/option.{type Option}
import gleam/pair
import gleam/result
import gleam/string_builder.{type StringBuilder}
import gleam/int

// TYPES -----------------------------------------------------------------------

/// A `Codec` describes both an encoder and a decoder for a given type. For example,
/// under the hood the `int` codec looks like this:
///
/// ```gleam
/// pub fn int() -> Codec(Int) {
///   Codec(
///     encode: json.int,
///     decode: dynamic.int
///   )
/// }
/// ```
///
/// Why is this useful? Writing decoders and encoders is tedious. Gleam doesn't
/// have any metaprogramming features to derive or generate these for us, so we're
/// stuck writing them. With `Codec`s you only need to write them once to get both
/// an encoder and a decoder!
///
/// Importantly, the codec API means our encoders and decoders stay _isomorphic_.
/// That is, we can guarantee that the conversions to JSON and from `Dynamic` are
/// always in sync. 
///
pub opaque type Codec(a) {
  Codec(
    encode: fn(a) -> Json,
    decode: fn(Dynamic) -> Result(a, List(DynamicError)),
  )
}

///
///
pub opaque type Custom(a) {
  Custom(encode: fn(a) -> Json, decode: Map(String, Decoder(a)))
}

///
///
pub type Encoder(a) =
  fn(a) -> Json

///
///
pub type Decoder(a) =
  fn(Dynamic) -> Result(a, List(DynamicError))

// CONSTRUCTORS ----------------------------------------------------------------

///
///
pub fn from(encode: Encoder(a), decode: Decoder(a)) -> Codec(a) {
  Codec(encode, decode)
}

///
///
pub fn succeed(a: a) -> Codec(a) {
  Codec(encode: fn(_) { json.null() }, decode: fn(_) { Ok(a) })
}

///
///
pub fn fail(err: DynamicError) -> Codec(a) {
  Codec(encode: fn(_) { json.null() }, decode: fn(_) { Error([err]) })
}

// CONSTRUCTORS: PRIMITIVES ----------------------------------------------------

///
///
pub fn int() -> Codec(Int) {
  Codec(encode: json.int, decode: dynamic.int)
}

///
///
pub fn float() -> Codec(Float) {
  Codec(encode: json.float, decode: dynamic.float)
}

///
///
pub fn string() -> Codec(String) {
  Codec(encode: json.string, decode: dynamic.string)
}

///
///
pub fn bool() {
  Codec(encode: json.bool, decode: dynamic.bool)
}

// CONSTRUCTORS: CONTAINERS ----------------------------------------------------

///
///
pub fn list(codec: Codec(a)) -> Codec(List(a)) {
  let encode = json.array(_, codec.encode)
  let decode = dynamic.list(codec.decode)

  Codec(encode, decode)
}

///
///
pub fn optional(codec: Codec(a)) -> Codec(Option(a)) {
  let encode = json.nullable(_, codec.encode)
  let decode = dynamic.optional(codec.decode)

  Codec(encode, decode)
}

///
///
pub fn object(codec: Codec(a)) -> Codec(Map(String, a)) {
  let encode = fn(map) {
    map
    |> map.to_list
    |> list.map(pair.map_second(_, codec.encode))
    |> json.object
  }
  let decode = dynamic.map(dynamic.string, codec.decode)

  Codec(encode, decode)
}

///
///
pub fn dictionary(key_codec: Codec(k), val_codec: Codec(v)) -> Codec(Map(k, v)) {
  list(tuple2(key_codec, val_codec))
  |> map(map.to_list, map.from_list)
}

///
///
pub fn result(ok_codec: Codec(a), error_codec: Codec(e)) -> Codec(Result(a, e)) {
  custom({
    use ok <- variant1("Ok", Ok, ok_codec)
    use error <- variant1("Error", Error, error_codec)
    use value <- make_custom

    case value {
      Ok(a) -> ok(a)
      Error(e) -> error(e)
    }
  })
}

///
///
pub fn tuple2(codec_a: Codec(a), codec_b: Codec(b)) -> Codec(#(a, b)) {
  let constructor = fn(a, b) { #(a, b) }

  custom({
    use tuple <- variant2("Tuple2", constructor, codec_a, codec_b)
    use value <- make_custom
    let #(a, b) = value

    tuple(a, b)
  })
}

///
///
pub fn tuple3(
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
) -> Codec(#(a, b, c)) {
  let constructor = fn(a, b, c) { #(a, b, c) }

  custom({
    use tuple <- variant3("Tuple3", constructor, codec_a, codec_b, codec_c)
    use value <- make_custom
    let #(a, b, c) = value

    tuple(a, b, c)
  })
}

// CONSTRUCTORS: CUSTOM TYPES --------------------------------------------------

pub fn custom(builder: Custom(a)) -> Codec(a) {
  Codec(
    encode: builder.encode,
    decode: fn(dyn) {
      let decode_tag = dynamic.field("$", dynamic.string)
      use tag <- result.then(decode_tag(dyn))

      case map.get(builder.decode, tag) {
        Ok(decoder) -> decoder(dyn)
        Error(_) -> Error([DynamicError("Unknown tag", tag, ["$"])])
      }
    },
  )
}

pub opaque type Variant(a) {
  Variant
}

pub fn variant(
  tag: String,
  variant: Variant(a),
  builder: fn(a) -> Custom(result),
) -> Custom(result) {
  todo
}

pub fn arg(
  codec: Codec(a),
  builder: fn(Int) -> List(Decoder(Dynamic)),
) -> fn(Int) -> List(Decoder(Dynamic)) {
  fn(index) {
    let decoder = fn(dyn) {
      let decode = dynamic.field(int.to_string(index), codec.decode)
      use a <- result.map(decode(dyn))

      dynamic.from(a)
    }

    [decoder, ..builder(index + 1)]
  }
}

pub fn make_variant(_: Int) -> List(Decoder(Dynamic)) {
  []
}

pub fn make_custom(encode: fn(a) -> Json) -> Custom(a) {
  Custom(encode, decode: map.new())
}

pub fn variant0(
  tag: String,
  constructor: result,
  builder: fn(Json) -> Custom(result),
) -> Custom(result) {
  let encoder = json.object([#("$", json.string(tag))])
  let decoder = fn(_) { Ok(constructor) }
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant1(
  tag: String,
  constructor: fn(a) -> result,
  codec_a: Codec(a),
  builder: fn(fn(a) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a) {
    json.object([#("$", json.string(tag)), #("0", codec_a.encode(a))])
  }
  let decoder = dynamic.decode1(constructor, dynamic.field("0", codec_a.decode))
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant2(
  tag: String,
  constructor: fn(a, b) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  builder: fn(fn(a, b) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
    ])
  }
  let decoder =
    dynamic.decode2(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant3(
  tag: String,
  constructor: fn(a, b, c) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  builder: fn(fn(a, b, c) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
    ])
  }
  let decoder =
    dynamic.decode3(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant4(
  tag: String,
  constructor: fn(a, b, c, d) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  codec_d: Codec(d),
  builder: fn(fn(a, b, c, d) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c, d) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
      #("3", codec_d.encode(d)),
    ])
  }
  let decoder =
    dynamic.decode4(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
      dynamic.field("3", codec_d.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant5(
  tag: String,
  constructor: fn(a, b, c, d, e) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  codec_d: Codec(d),
  codec_e: Codec(e),
  builder: fn(fn(a, b, c, d, e) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c, d, e) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
      #("3", codec_d.encode(d)),
      #("4", codec_e.encode(e)),
    ])
  }
  let decoder =
    dynamic.decode5(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
      dynamic.field("3", codec_d.decode),
      dynamic.field("4", codec_e.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant6(
  tag: String,
  constructor: fn(a, b, c, d, e, f) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  codec_d: Codec(d),
  codec_e: Codec(e),
  codec_f: Codec(f),
  builder: fn(fn(a, b, c, d, e, f) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c, d, e, f) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
      #("3", codec_d.encode(d)),
      #("4", codec_e.encode(e)),
      #("5", codec_f.encode(f)),
    ])
  }
  let decoder =
    dynamic.decode6(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
      dynamic.field("3", codec_d.decode),
      dynamic.field("4", codec_e.decode),
      dynamic.field("5", codec_f.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant7(
  tag: String,
  constructor: fn(a, b, c, d, e, f, g) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  codec_d: Codec(d),
  codec_e: Codec(e),
  codec_f: Codec(f),
  codec_g: Codec(g),
  builder: fn(fn(a, b, c, d, e, f, g) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c, d, e, f, g) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
      #("3", codec_d.encode(d)),
      #("4", codec_e.encode(e)),
      #("5", codec_f.encode(f)),
      #("6", codec_g.encode(g)),
    ])
  }
  let decoder =
    dynamic.decode7(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
      dynamic.field("3", codec_d.decode),
      dynamic.field("4", codec_e.decode),
      dynamic.field("5", codec_f.decode),
      dynamic.field("6", codec_g.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

pub fn variant8(
  tag: String,
  constructor: fn(a, b, c, d, e, f, g, h) -> result,
  codec_a: Codec(a),
  codec_b: Codec(b),
  codec_c: Codec(c),
  codec_d: Codec(d),
  codec_e: Codec(e),
  codec_f: Codec(f),
  codec_g: Codec(g),
  codec_h: Codec(h),
  builder: fn(fn(a, b, c, d, e, f, g, h) -> Json) -> Custom(result),
) -> Custom(result) {
  let encoder = fn(a, b, c, d, e, f, g, h) {
    json.object([
      #("$", json.string(tag)),
      #("0", codec_a.encode(a)),
      #("1", codec_b.encode(b)),
      #("2", codec_c.encode(c)),
      #("3", codec_d.encode(d)),
      #("4", codec_e.encode(e)),
      #("5", codec_f.encode(f)),
      #("6", codec_g.encode(g)),
      #("7", codec_h.encode(h)),
    ])
  }
  let decoder =
    dynamic.decode8(
      constructor,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
      dynamic.field("2", codec_c.decode),
      dynamic.field("3", codec_d.decode),
      dynamic.field("4", codec_e.decode),
      dynamic.field("5", codec_f.decode),
      dynamic.field("6", codec_g.decode),
      dynamic.field("7", codec_h.decode),
    )
  let builder = builder(encoder)

  Custom(..builder, decode: map.insert(builder.decode, tag, decoder))
}

// QUERIES ---------------------------------------------------------------------

///
///
pub fn encoder(codec: Codec(a)) -> Encoder(a) {
  codec.encode
}

///
///
pub fn decoder(codec: Codec(a)) -> Decoder(a) {
  codec.decode
}

// MANIPULATIONS ---------------------------------------------------------------

///
///
pub fn then(
  codec: Codec(a),
  from: fn(b) -> a,
  to: fn(a) -> Codec(b),
) -> Codec(b) {
  Codec(
    encode: fn(b) {
      let a = from(b)
      codec.encode(a)
    },
    decode: fn(dyn) {
      use a <- result.then(codec.decode(dyn))
      to(a).decode(dyn)
    },
  )
}

///
///
pub fn map(codec: Codec(a), from: fn(b) -> a, to: fn(a) -> b) -> Codec(b) {
  use a <- then(codec, from)
  succeed(to(a))
}

// CONVERSIONS -----------------------------------------------------------------

///
///
pub fn encode_json(value: a, codec: Codec(a)) -> Json {
  codec.encode(value)
}

///
///
pub fn encode_string(value: a, codec: Codec(a)) -> String {
  codec.encode(value)
  |> json.to_string
}

///
///
pub fn encode_string_custom_from(value: a, codec: Codec(a)) -> StringBuilder {
  codec.encode(value)
  |> json.to_string_builder
}

///
///
pub fn decode_string(json: String, codec: Codec(a)) -> Result(a, JsonError) {
  json.decode(json, codec.decode)
}

///
///
pub fn decode_dynamic(
  dynamic: Dynamic,
  codec: Codec(a),
) -> Result(a, List(DynamicError)) {
  codec.decode(dynamic)
}
