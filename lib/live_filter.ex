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
              draw_boxes: [
                spec:
                  false
                  | (Vix.Vips.Image.t(), detected_objects :: [map()] -> Vix.Vips.Image.t()),
                default: false,
                description: """
                Function used to draw bounding boxes on the image. If set to `false`,
                the detected objects will be added to the buffer metadata under
                `:detected_objects` key instead of drawing.

                Defaults to `false`.

                The function will receive two arguments:
                  - `Vix.Vips.Image.t()` - image on which to draw the boxes
                  - `detected_objects` - list of detected objects in the format returned by
                    `YOLO.to_detected_objects/2`.

                The simplest way to draw boxes is to pass `KinoYOLO.Draw.draw_detected_objects/2`
                function from [kino_yolo](https://github.com/poeticoding/kino_yolo)
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
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
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
         [
           state.yolo_model,
           state.draw_boxes,
           state.additional_latency,
           stream_format,
           state.parent_process
         ]}
      )

    {[], %{state | model_runner: model_runner}}
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
