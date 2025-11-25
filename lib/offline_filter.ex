defmodule Membrane.YOLO.OfflineFilter do
  @moduledoc """
  A Membrane filter that performs object detection on video frames.

  This filter uses a YOLO model to detect objects in incoming video frames. It can either draw bounding
  boxes on the frames or add detected objects to buffers metadata.

  Object detection is performed on every incoming frame.

  If you want to perform real-time object detection, consider using `Membrane.YOLO.LiveFilter` instead.
  """

  use Membrane.Filter

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
  def handle_buffer(:input, buffer, ctx, state) do
    {:ok, image} =
      Membrane.RawVideo.payload_to_image(buffer.payload, ctx.pads.input.stream_format)

    detected_objects =
      state.yolo_model
      |> YOLO.detect(image, frame_scaler: YOLO.FrameScalers.ImageScaler)
      |> YOLO.to_detected_objects(state.yolo_model.classes)

    image =
      case state.draw_boxes do
        false -> image
        draw_fun when is_function(draw_fun, 2) -> draw_fun.(image, detected_objects)
      end

    {:ok, payload, _stream_format} = Membrane.RawVideo.image_to_payload(image)
    buffer = %Membrane.Buffer{buffer | payload: payload}

    buffer =
      case state.draw_boxes do
        false ->
          %Membrane.Buffer{
            buffer
            | metadata: Map.put(buffer.metadata, :detected_objects, detected_objects)
          }

        draw_fun when is_function(draw_fun, 2) ->
          buffer
      end

    {[buffer: {:output, buffer}], state}
  end
end
