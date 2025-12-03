defmodule Membrane.YOLO.Drawer do
  @moduledoc """
  """

  use Membrane.Filter

  def_input_pad :input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}
  def_output_pad :output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB}

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{}}

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    if not is_map_key(buffer.metadata, :detected_objects) do
      raise """
      Buffer metadata does not contain `:detected_objects` key.
      Make sure that the previous element in the pipeline is a Membrane.YOLO.Detector
      that adds detection results to the buffer metadata.
      """
    end

    {:ok, image} =
      Membrane.RawVideo.payload_to_image(buffer.payload, ctx.pads.input.stream_format)

    image = __MODULE__.DrawUtils.draw_detected_objects(image, buffer.metadata.detected_objects)
    {:ok, new_payload, _stream_format} = Membrane.RawVideo.image_to_payload(image)

    buffer = %Membrane.Buffer{buffer | payload: new_payload}
    {[buffer: {:output, buffer}], state}
  end
end
