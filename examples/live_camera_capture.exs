hardware_acceleration =
  case :os.type() do
    {:unix, :darwin} -> :coreml
    {:unix, :linux} -> :cuda
  end

Mix.install(
  [
    {:membrane_yolo_plugin, path: Path.join(__DIR__, "..")},
    {:membrane_core, "~> 1.0"},
    {:membrane_camera_capture_plugin, "~> 0.7.4"},
    {:membrane_ffmpeg_swscale_plugin, "~> 0.16.3"},
    {:boombox, "~> 0.2.8"},
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

defmodule YOLO.CameraCapture.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:camera_capture, Membrane.CameraCapture)
      |> child(:swscale_converter, %Membrane.FFmpeg.SWScale.Converter{
        format: :RGB,
        output_width: 640
      })
      |> child(:yolo_detector, %Membrane.YOLO.Detector{
        mode: :live_low_latency,
        yolo_model:
          YOLO.load(
            model_impl: YOLO.Models.YOLOX,
            model_path: "examples/models/yolox_l.onnx",
            classes_path: "examples/models/coco_classes.json",
            eps: [unquote(hardware_acceleration)]
          )
      })
      |> child(:yolo_drawer, Membrane.YOLO.Drawer)
      |> via_in(:input, options: [kind: :video])
      |> child(:boombox_sink, %Boombox.Bin{output: :player})

    {[spec: spec], %{}}
  end
end

{:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(YOLO.CameraCapture.Pipeline, [])
Process.monitor(pipeline)

receive do
  {:DOWN, _ref, :process, _pid, _reason} -> :ok
end
