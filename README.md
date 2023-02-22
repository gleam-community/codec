# gleam-community/codec

A package for keeping your JSON encoders and decoders in sync.

[![Package Version](https://img.shields.io/hexpm/v/gleam_community_codec)](https://hex.pm/packages/gleam_community_codec)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleam_community_codec/)

✨ This project is written in pure Gleam so you can use it anywhere Gleam runs:
Erlang, Elixir, Node, Deno, and the browser!

---

## Quickstart

```gleam
import gleam_community/codec

pub type Colour {
  RGB(Int, Int, Int)
  Name(String)
}

pub fn colour_codec() {
  codec.custom3(fn(rgb, name, value) {
    case value {
      RGB(r, g, b) -> rgb(r, g, b)
      Name(name) -> name(name)
    }
  })
  |> codec.variant3("RGB", RGB, codec.int(), codec.int(), codec.int())
  |> codec.variant1("Name", Name, codec.string())
  |> codec.construct
}
```

## Installation

`gleam-community` packages are published to [hex.pm](https://hex.pm/packages/gleam_community_codec)
with the prefix `gleam_community_`. You can add them to your Gleam projects directly:

```sh
gleam add gleam_community_codec
```

The docs can be found over at [hexdocs.pm](https://hexdocs.pm/gleam_community_codec).
