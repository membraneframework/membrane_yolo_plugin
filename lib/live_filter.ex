defmodule Membrane.YOLO.LiveFilter do
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
              draw_boxes?: [
                spec: boolean(),
                default: true,
                description: """
                If set to `true`, bounding boxes will be drawn on the frames.
                If set to `false`, the detected objects map will be added to the buffer metadata.

                Defaults to `true`.
                """
              ],
              low_latency_mode?: [
                spec: boolean(),
                default: false,
                description: """
                When set to `true`, the filter will operate in low-latency mode.

                In this mode, the latency introduced by the filter is minimal, however
                bounding boxes will be delayed related to the frames they correspond to.

                When this flag is set to `false`, the filter latency will equal at least
                the time taken by the model to process a single frame, but bounding boxes
                will match the objects in the stream better.

                Defaults to `false`.

                Option `additional_latency` can be used only if this mode is disabled.
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

                This option can be used only when `low_latency_mode?` is not set or it is set
                to `false`.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    if opts.low_latency_mode? and opts.additional_latency != Membrane.Time.seconds(0) do
      raise "`additional_latency` option cannot be used when `low_latency_mode?` is set to `true`"
    end

    state =
      opts
      |> Map.from_struct()
      |> Map.put(:model_runner, nil)

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, ctx, state) do
    {:ok, model_runner} =
      Membrane.UtilitySupervisor.start_link_child(
        ctx.utility_supervisor,
        {__MODULE__.ModelRunner,
         %__MODULE__.ModelRunner.Opts{
           yolo_model: state.yolo_model,
           draw_boxes?: state.draw_boxes?,
           additional_latency: state.additional_latency,
           low_latency_mode?: state.low_latency_mode?,
           stream_format: stream_format,
           parent_process: self()
         }}
      )

    {[stream_format: {:output, stream_format}], %{state | model_runner: model_runner}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    __MODULE__.ModelRunner.process_buffer(state.model_runner, buffer)
    {[], state}
  end

  @impl true
  def handle_info({:processed_buffer, buffer}, _ctx, state) do
    {[buffer: {:output, buffer}], state}
  end
end
