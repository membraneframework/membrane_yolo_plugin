defmodule Membrane.YOLO.Drawer.DrawUtils do
  @moduledoc false

  # This moddule contains slightly modified code from kino_yolo
  #   - to avoid adding kino to dependencies
  #   - to avoid having GitHub dependency in order to publish this package on Hex
  #   - and improve colors of drawn boxes.

  # Original code source:
  #   - https://github.com/poeticoding/kino_yolo/blob/main/lib/kino_yolo/draw.ex
  #   - https://github.com/poeticoding/kino_yolo/blob/main/lib/kino_yolo/colors.ex

  @class_colors [
                  "#FF0000",
                  "#00FF00",
                  "#0000FF",
                  "#4d4d33",
                  "#FF00FF",
                  "#006060",
                  "#800000",
                  "#008000",
                  "#000080",
                  "#FF00FF",
                  "#800080",
                  "#008080",
                  "#3a3a3a",
                  "#FFA500",
                  "#A52A2A",
                  "#8A2BE2",
                  "#5F9EA0",
                  "#468c00",
                  "#D2691E",
                  "#FF7F50",
                  "#6495ED",
                  "#DC143C",
                  "#027777",
                  "#00008B",
                  "#008B8B",
                  "#785808",
                  "#6e6d6d",
                  "#006400",
                  "#5a5733",
                  "#8B008B",
                  "#556B2F",
                  "#7d4500",
                  "#9932CC",
                  "#8B0000",
                  "#58382e",
                  "#3f553f",
                  "#483D8B",
                  "#2F4F4F",
                  "#006567",
                  "#9400D3",
                  "#FF1493",
                  "#006080",
                  "#696969",
                  "#003b76",
                  "#B22222",
                  "#433a29",
                  "#228B22",
                  "#FF00FF",
                  "#392424",
                  "#3d3d40",
                  "#6d5d02",
                  "#896713",
                  "#501616",
                  "#3b6300",
                  "#2f422f",
                  "#FF69B4",
                  "#CD5C5C",
                  "#4B0082",
                  "#4f4f1e",
                  "#5e5612",
                  "#1b1b43",
                  "#482330",
                  "#374e21",
                  "#7f7300",
                  "#065671",
                  "#F08080",
                  "#166464",
                  "#3f3f16",
                  "#651a1a",
                  "#008d00",
                  "#9f0018",
                  "#a72f00",
                  "#008680",
                  "#00588e",
                  "#0051a2",
                  "#003275",
                  "#505000",
                  "#005028",
                  "#4682B4",
                  "#7e4800",
                  "#008080",
                  "#ff00ff",
                  "#FF6347",
                  "#00796d",
                  "#7c437c",
                  "#b07404",
                  "#f46767",
                  "#c430a6"
                ]
                |> Enum.with_index(&{&2, &1})
                |> Map.new()

  @stroke_width 3
  @description_label_font_size 21
  @class_label_font_size 18

  defp class_color(class_idx) do
    Map.get(@class_colors, class_idx, "#FF0000")
  end

  @spec draw_detected_objects(
          image :: Vix.Vips.Image.t(),
          detected_objects :: [map()],
          options :: Keyword.t()
        ) :: Vix.Vips.Image.t()
  def draw_detected_objects(image, detected_objects, options \\ []) do
    description = Keyword.get(options, :description)
    classes = Keyword.get(options, :classes)

    # filter detected objects by classes
    detected_objects =
      if classes do
        Enum.filter(detected_objects, fn detection ->
          detection.class in classes or detection.class_idx in classes
        end)
      else
        detected_objects
      end

    # draw detected objects
    image_with_detections = Enum.reduce(detected_objects, image, &draw_object_detection(&2, &1))

    # add description label
    if description do
      # creating description label
      desc_label = description_label_image(description)

      {full_width, full_height, _bands} = Image.shape(image)
      {desc_width, desc_height, _bands} = Image.shape(desc_label)

      Image.Draw.image!(
        image_with_detections,
        desc_label,
        full_width - desc_width,
        full_height - desc_height
      )
    else
      image_with_detections
    end
  end

  defp draw_object_detection(image, %{bbox: bbox} = detection) do
    left = max(round(bbox.cx - bbox.w / 2), 0)
    top = max(round(bbox.cy - bbox.h / 2), 0)
    color = class_color(detection.class_idx)

    class_label = class_label_image(detection)
    {_width, text_height, _bands} = Image.shape(class_label)

    image
    |> Image.Draw.rect!(left, top, bbox.w, bbox.h,
      stroke_width: @stroke_width,
      color: color,
      fill: false
    )
    |> Image.Draw.image!(class_label, left, max(top - text_height - 2, 0))
  end

  defp class_label_image(detection) do
    color = class_color(detection.class_idx)
    prob = round(detection.prob * 100)

    Image.Text.simple_text!("#{detection.class} #{prob}%",
      text_fill_color: "white",
      font_size: @class_label_font_size
    )
    |> Image.Text.add_background_padding!(background_fill_color: color, padding: [5, 5])
    |> Image.Text.add_background!(background_fill_color: color)
    |> Image.split_alpha()
    |> elem(0)
  end

  defp description_label_image(text) do
    Image.Text.simple_text!(text,
      text_fill_color: "white",
      font_size: @description_label_font_size
    )
    |> Image.Text.add_background_padding!(background_fill_color: "#0000FF", padding: [5, 5])
    |> Image.Text.add_background!(background_fill_color: "#0000FF")
    |> Image.split_alpha()
    |> elem(0)
  end
end
