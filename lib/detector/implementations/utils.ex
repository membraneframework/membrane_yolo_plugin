defmodule Membrane.YOLO.Detector.Implementations.Utils do
  @moduledoc false

  alias Membrane.Buffer
  alias Membrane.YOLO.Detector.State

  @spec start_link_detection_task(
          buffer :: Buffer.t(),
          ctx :: Membrane.Element.CallbackContext.t(),
          state :: State.t()
        ) :: {:ok, pid()}
  def start_link_detection_task(buffer, ctx, %State{} = state) do
    my_pid = self()

    Task.start_link(fn ->
      {:ok, image} =
        Membrane.RawVideo.payload_to_image(buffer.payload, ctx.pads.input.stream_format)

      detected_objects =
        state.yolo_model
        |> YOLO.detect(image, frame_scaler: YOLO.FrameScalers.ImageScaler)
        |> YOLO.to_detected_objects(state.yolo_model.classes)

      GenServer.cast(my_pid, {:detection_complete, detected_objects})
    end)
  end

  @spec update_buffer_metadata(Buffer.t(), list()) :: Buffer.t()
  def update_buffer_metadata(buffer, detected_objects) do
    metadata = buffer.metadata |> Map.put(:detected_objects, detected_objects || [])
    %Buffer{buffer | metadata: metadata}
  end
end
