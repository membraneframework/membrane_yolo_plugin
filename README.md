# Membrane YOLO Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_yolo_plugin.svg)](https://hex.pm/packages/membrane_yolo_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_yolo_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_yolo_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_yolo§  §_plugin)

Contains 2 Membrane Filters
 - `Membrane.YOLO.LiveFilter`
 - `Membrane.YOLO.OfflineFilter`
to run YOLO object detection on a video stream in live and offline scaneario.

Uses under the hood [yolo_elixir](https://github.com/poeticoding/yolo_elixir).

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_yolo_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_yolo_plugin, "~> 0.1.0"}
  ]
end
```

## Examples

See `examples/yolo.livemd` or `examples/live_camera_capture.exs`, `examples/live_mp4_processing.exs` and `examples/offline_mp4_processing.exs`

## Copyright and License

Copyright 2025, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_yolo_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_yolo_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
