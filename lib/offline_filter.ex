defmodule Membrane.YOLO.OfflineFilter do
  @moduledoc """
  A Membrane filter that performs object detection on video frames.

  This filter uses a YOLO model to detect objects in incoming video frames. It can either draw bounding
  boxes on the frames or add detected objects to buffers metadata.

  Object detection is performed on every incoming frame.

  If you want to perform real-time object detection, consider using `Membrane.YOLO.LiveFilter` instead.
  """

  use Membrane.Filter

  alias Membrane.YOLO.DrawUtils

  def_input_pad :input,
    accepted_format: %Membrane.RawVideo{pixel_format: :RGB},
    flow_control: :manual,
    demand_unit: :buffers

  def_output_pad :output,
    accepted_format: %Membrane.RawVideo{pixel_format: :RGB},
    flow_control: :manual,
    demand_unit: :buffers

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
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state = Map.from_struct(opts)
    {[], state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {[demand: {:input, size}], state}
  end

  @impl true
  @spec handle_buffer(:input, Membrane.Buffer.t(), any(), any()) ::
          {[{:buffer, {any(), any()}}, ...], any()}
  def handle_buffer(:input, buffer, ctx, state) do
    {:ok, image} =
      Membrane.RawVideo.payload_to_image(buffer.payload, ctx.pads.input.stream_format)

    detected_objects =
      state.yolo_model
      |> YOLO.detect(image, frame_scaler: YOLO.FrameScalers.ImageScaler)
      |> YOLO.to_detected_objects(state.yolo_model.classes)

    {image, metadata} =
      if state.draw_boxes? do
        {
          image |> DrawUtils.draw_detected_objects(detected_objects),
          buffer.metadata
        }
      else
        {
          image,
          buffer.metadata |> Map.put(:detected_objects, detected_objects)
        }
      end

    {:ok, payload, _stream_format} = Membrane.RawVideo.image_to_payload(image)
    buffer = %Membrane.Buffer{buffer | payload: payload, metadata: metadata}

    {[buffer: {:output, buffer}], state}
  end
end
