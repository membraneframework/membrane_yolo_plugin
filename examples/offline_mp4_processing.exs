hardware_acceleration =
  case :os.type() do
    {:unix, :darwin} -> :coreml
    {:unix, :linux} -> :cuda
  end

Mix.install(
  [
    {:membrane_yolo_plugin,
     github: "membraneframework/membrane_yolo_plugin", branch: "implementation"},
    {:membrane_core, "~> 1.0"},
    {:membrane_camera_capture_plugin, "~> 0.7.3"},
    {:membrane_ffmpeg_swscale_plugin, "~> 0.16.3"},
    {:membrane_raw_video_format,
     github: "membraneframework/membrane_raw_video_format", branch: "to_image", override: true},
    {:boombox, github: "membraneframework/boombox"},
    {:kino_yolo, github: "poeticoding/kino_yolo"},
    {:exla, "~> 0.10"}
  ],
  config: [
    logger: [level: :info],
    ortex: [
      {Ortex.Native, [features: [hardware_acceleration]]}
    ],
    nx: [
      default_backend: EXLA.Backend
    ]
  ]
)

model_name = "yolox_l.onnx"
model_path = Path.join("examples/models", model_name)

if not File.exists?(model_path) do
  model_url =
    "https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/#{model_name}"

  %{body: data} = Req.get!(model_url)
  File.write!(model_path, data)
end

result_file_path = "examples/outputs/street_bounding_boxes.mp4"

defmodule YOLOMP4Pipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:mp4_source, %Boombox.Bin{input: "examples/fixtures/street_short.mp4"})
      |> via_out(:output, options: [kind: :video])
      |> child(:transcoder, %Membrane.Transcoder{output_stream_format: Membrane.RawVideo})
      |> child(:rgb_converter, %Membrane.FFmpeg.SWScale.Converter{
        format: :RGB,
        output_width: 640
      })
      |> child(:yolo_live_filter, %Membrane.YOLO.OfflineFilter{
        yolo_model:
          YOLO.load(
            model_impl: YOLO.Models.YOLOX,
            model_path: "examples/models/yolox_l.onnx",
            classes_path: "examples/models/coco_classes.json",
            eps: [unquote(hardware_acceleration)]
          ),
        draw_boxes: &KinoYOLO.Draw.draw_detected_objects/2
      })
      |> child(:debug_logger, %Membrane.Debug.Filter{
        handle_buffer: fn buffer ->
          pts_ms = Membrane.Time.as_milliseconds(buffer.pts, :round)

          Membrane.Logger.info("""
          Processed #{inspect(pts_ms)} ms of 10_000 ms of fixture video
          """)
        end
      })
      |> child(:i420_converter, %Membrane.FFmpeg.SWScale.Converter{
        format: :I420
      })
      |> via_in(:input, options: [kind: :video])
      |> child(:boombox_sink, %Boombox.Bin{output: unquote(result_file_path)})

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(:processing_finished, :boombox_sink, _ctx, state) do
    {[terminate: :normal], state}
  end
end

{:ok, supervisor, _pipeline} = Membrane.Pipeline.start_link(YOLOMP4Pipeline, [])
Process.monitor(supervisor)

receive do
  {:DOWN, _ref, :process, _pid, :normal} -> :ok
end

Boombox.play(result_file_path)
