hardware_acceleration =
  case :os.type() do
    {:unix, :darwin} -> :coreml
    {:unix, :linux} -> :cuda
  end

Mix.install(
  [
    {:membrane_yolo_plugin, path: "/Users/feliks/membrane/membrane_yolo_plugin"},
    {:membrane_core, "~> 1.0"},
    {:membrane_camera_capture_plugin, "~> 0.7.3"},
    {:membrane_ffmpeg_swscale_plugin, "~> 0.16.3"},
    {:membrane_raw_video_format,
     github: "membraneframework/membrane_raw_video_format", branch: "to_image", override: true},
    {:boombox, path: "~/membrane/boombox"},
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

defmodule YOLOMP4Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:mp4_source, %Boombox.Bin{input: "examples/fixtures/street.mp4"})
      |> via_out(:output, options: [kind: :video])
      |> child(:transcoder, %Membrane.Transcoder{output_stream_format: Membrane.RawVideo})
      |> child(:swscale_converter, %Membrane.FFmpeg.SWScale.Converter{
        format: :RGB,
        output_width: 640
      })
      |> child(:yolo_live_filter, %Membrane.YOLO.LiveFilter{
        yolo_model:
          YOLO.load(
            model_impl: YOLO.Models.YOLOX,
            model_path: "examples/models/yolox_l.onnx",
            classes_path: "examples/models/coco_classes.json",
            eps: [unquote(hardware_acceleration)]
          ),
        draw_boxes: &KinoYOLO.Draw.draw_detected_objects/2
      })
      |> via_in(:input, options: [kind: :video])
      |> child(:boombox_sink, %Boombox.Bin{output: :player})

    {[spec: spec], %{}}
  end
end

{:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(YOLOMP4Pipeline, [])
Process.monitor(pipeline)

receive do
  {:DOWN, _ref, :process, _pid, _reason} -> :ok
end
