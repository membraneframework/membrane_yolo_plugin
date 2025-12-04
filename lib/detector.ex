defmodule Membrane.YOLO.Detector do
  @moduledoc """
  A Membrane filter that performs real-time object detection on video frames.

  This filter uses a YOLO model to detect objects in incoming video frames. Detected objects
  are added to the metadata of the output buffers.

  It can work in three modes: `:offline`, `:live`, and `:live_low_latency`.
  Take a look at the description of `:mode` option for more details.

  If you want to draw bounding boxes around detected objects, plug `Membrane.YOLO.Drawer`
  just after this filter in your pipeline.

  It uses under the hood `:yolo` package from hex.pm.
  """

  use Membrane.Filter

  def_input_pad :input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}
  def_output_pad :output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}

  def_options yolo_model: [
                spec: YOLO.Model.t(),
                description: """
                YOLO model used for inference. The result of `YOLO.load/1`.
                """
              ],
              mode: [
                spec: :offline | :live | :live_low_latency,
                description: """
                The mode in which the filter operates.
                - `:offline` - performs object detection on every frame.
                - `:live` - performs real-time object detection on every N-th frame,
                  where N is dynamically determined to maintain real-time performance. Then object
                  detection results are propagated on neighboring frames. In this mode, the filter
                  adds latency that is bigger or equal to the time needed to perform object detection
                  on a single frame. Take a look at `additional_latency` option docs for more details.
                - `:live_low_latency` - works very similarly to `:live` mode, but it doesn't add
                  latency to the stream. However, bounding boxes may be delayed related to the frames
                  they correspond to. The delay is not bigger than doubled time needed to perform object
                  detection on a single frame.
                """
              ],
              additional_latency: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(0),
                inspector: &Membrane.Time.inspect/1,
                description: """
                The additional latency that might be used to avoid sending chunks of buffers by
                `#{inspect(__MODULE__)}`.

                Defaults to `0` seconds.

                This option can be used only when `:mode?` is set to `:live`.

                When set, it will be added to the initial latency introduced by the filter.
                Increasing its value will lower the chance of sending any buffer too late
                comparing to the timestamp and moment of returning the first buffer. It is recommended
                to use it when you can tolerate some additional latency in favor of guaranteeing that
                no delayed buffers are returned. In most cases 500 milliseconds should be totally
                sufficient, however it depends on the performance of the hardware running the pipeline.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    if opts.mode != :live and opts.additional_latency != Membrane.Time.seconds(0) do
      raise "`additional_latency` option cannot be used when `mode` is not set to `:live`"
    end

    state = %__MODULE__.State{
      yolo_model: opts.yolo_model,
      mode: opts.mode,
      additional_latency: opts.additional_latency,
      impl: __MODULE__.Implementation.resolve_implementation(opts.mode)
    }

    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    state.impl.handle_buffer(buffer, ctx, state)
  end

  @impl true
  def handle_info(msg, ctx, state) do
    state.impl.handle_info(msg, ctx, state)
  end

  @impl true
  def handle_end_of_stream(:input, ctx, state) do
    state.impl.handle_end_of_stream(ctx, state)
  end
end
