hardware_acceleration =
  case :os.type() do
    {:unix, :darwin} -> :coreml
    {:unix, :linux} -> :cuda
  end

Mix.install(
  [
    {
      :membrane_yolo_plugin,
      github: "membraneframework/membrane_yolo_plugin", branch: "implementation"
    },
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
    ortex: [
      {Ortex.Native, [features: [hardware_acceleration]]}
    ],
    nx: [
      default_backend: EXLA.Backend
    ]
  ]
)

Logger.configure(level: :info)

model_name = "yolox_l.onnx"
model_path = Path.join("examples/models", model_name)

if not File.exists?(model_path) do
  model_url =
    "https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/#{model_name}"

  %{body: data} = Req.get!(model_url)
  File.write!(model_path, data)
end

defmodule YOLO.MP4.LivePipeline do
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
        additional_latency: Membrane.Time.milliseconds(500)
      })
      |> via_in(:input, options: [kind: :video])
      |> child(:boombox_sink, %Boombox.Bin{output: :player})

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(:processing_finished, :boombox_sink, ctx, state) do
    {[terminate: :normal], state}
  end
end

{:ok, supervisor, _pipeline} = Membrane.Pipeline.start_link(YOLO.MP4.LivePipeline, [])
Process.monitor(supervisor)

receive do
  {:DOWN, _ref, :process, _pid, _reason} -> :ok
end
