defmodule Membrane.YOLO.Detector do
  @moduledoc """
  A Membrane filter that performs real-time object detection on video frames.

  This filter uses a YOLO model to detect objects in incoming video frames. It can either draw bounding
  boxes on the frames or add detected objects to buffers metadata.

  The object detecion is performed only on every N-th frame to maintain real-time performance.
  The value of N is determined dynamically based on the model's performance and the input
  stream's framerate and it can change over time.

  If you want to perform offline object detection on all video frames at the expense of the possibility
  of processing stream slower than real-time, consider using `Membrane.YOLO.OfflineFilter` instead.
  """

  use Membrane.Filter

  def_input_pad :input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}
  def_output_pad :output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}

  def_options yolo_model: [
                spec: YOLO.Model.t(),
                description: """
                YOLO model used for inference. The result of `YOLO.load/2`.
                """
              ],
              mode: [
                spec: :offline | :live | :live_low_latency,
                description: """
                The mode in which the filter operates.
                - `:offline` - performs object detection on every frame.
                - `:live` - performs real-time object detection TODO continue.
                - `:live_low_latency` - performs real-time object detection with minimal latency, but
                  bounding boxes may be delayed related to the frames they correspond to.
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

                When set, it will be added to the initial latency introduced by the filter.
                Increasing its value will lower the chance of sending any buffer too late
                comparing to the timestamp and moment of returning the first buffer.

                This option can be used only when `:mode?` is set to `:live`.
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
end
