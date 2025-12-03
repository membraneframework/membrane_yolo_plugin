defmodule Membrane.YOLO.Detector.Implementations.Offline do
  @behaviour Membrane.YOLO.Detector.Implementation

  alias Membrane.YOLO.Detector.Implementations.Utils
  alias Membrane.YOLO.Detector.State

  @impl true
  def handle_buffer(buffer, ctx, %State{} = state) do
    {:ok, image} =
      Membrane.RawVideo.payload_to_image(buffer.payload, ctx.pads.input.stream_format)

    detected_objects =
      state.yolo_model
      |> YOLO.detect(image, frame_scaler: YOLO.FrameScalers.ImageScaler)
      |> YOLO.to_detected_objects(state.yolo_model.classes)

    {:ok, payload, _stream_format} = Membrane.RawVideo.image_to_payload(image)

    buffer =
      %Membrane.Buffer{buffer | payload: payload}
      |> Utils.update_buffer_metadata(detected_objects)

    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_info(message, _ctx, _state) do
    raise "Unhandled message: #{inspect(message)}"
  end
end
