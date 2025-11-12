# defmodule Membrane.YOLO.Utils do
#   @moduledoc false

#   @spec draw_boxes_or_update_metadata(
#           buffer :: Membrane.Buffer.t(),
#           detected_objects :: [map()],
#           draw_boxes :: false | (Vix.Vips.Image.t(), [map()] -> Vix.Vips.Image.t())
#         ) :: Membrane.Buffer.t()

#   def draw_boxes_or_update_metadata(buffer, detected_objects, false) do
#     metadata = buffer.metadata |> Map.put(:detected_objects, detected_objects)
#     %Membrane.Buffer{buffer | metadata: metadata}
#   end

#   def draw_boxes_or_update_metadata(buffer, detected_objects, draw_fun)
#       when is_function(draw_fun, 2) do
#     new_payload = draw_fun.(buffer.payload, detected_objects)
#     %Membrane.Buffer{buffer | payload: new_payload}
#   end
# end
