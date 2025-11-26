defmodule Membrane.YOLO.LiveFilter.ModelRunner do
  @moduledoc false
  use GenServer

  def start_link({yolo_model, draw_boxes, latency, stream_format, parent_process}) do
    GenServer.start_link(__MODULE__,
      yolo_model: yolo_model,
      draw_boxes: draw_boxes,
      latency: latency,
      stream_format: stream_format,
      parent_process: parent_process
    )
  end

  def process_buffer(pid, buffer) do
    GenServer.cast(pid, {:process_buffer, buffer})
  end

  @impl true
  def init(opts) do
    state =
      Map.new(opts)
      |> Map.merge(%{
        detection_in_progress?: false,
        buffers_qex: Qex.new(),
        first_buffer_ts: nil,
        first_buffer_monotonic_time: nil
      })

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_buffer, buffer}, state) do
    if not state.detection_in_progress? do
      my_pid = self()

      Task.start_link(fn ->
        {:ok, image} =
          Membrane.RawVideo.payload_to_image(buffer.payload, state.stream_format)

        detected_objects =
          state.yolo_model
          |> YOLO.detect(image, frame_scaler: YOLO.FrameScalers.ImageScaler)
          |> YOLO.to_detected_objects(state.yolo_model.classes)

        GenServer.cast(my_pid, {:detection_complete, detected_objects})
      end)
    end

    state = state |> Map.update!(:buffers_qex, &Qex.push(&1, buffer))
    {:noreply, %{state | detection_in_progress?: true}}
  end

  @impl true
  def handle_cast({:detection_complete, detected_objects}, state) do
    state =
      state.buffers_qex
      |> Enum.reduce(state, fn buffer, state ->
        buffer = buffer |> maybe_draw_boxes(detected_objects, state)
        send_buffer(buffer, state)
      end)

    state = %{state | detection_in_progress?: false, buffers_qex: Qex.new()}

    {:noreply, state}
  end

  defp maybe_draw_boxes(buffer, detected_objects, state) do
    case state.draw_boxes do
      false ->
        %Membrane.Buffer{
          buffer
          | metadata: Map.put(buffer.metadata, :detected_objects, detected_objects)
        }

      draw_fun when is_function(draw_fun, 2) ->
        {:ok, image} =
          Membrane.RawVideo.payload_to_image(buffer.payload, state.stream_format)

        image = draw_fun.(image, detected_objects)
        {:ok, new_payload, _stream_format} = Membrane.RawVideo.image_to_payload(image)
        %Membrane.Buffer{buffer | payload: new_payload}
    end
  end

  defp send_buffer(buffer, state) when state.latency == nil do
    send(state.parent_process, {:processed_buffer, buffer})
    state
  end

  defp send_buffer(buffer, state) do
    state =
      if state.first_buffer_ts == nil,
        do: handle_first_buffer(buffer, state),
        else: state

    ts_diff = buffer.pts - state.first_buffer_ts
    desired_time = state.first_buffer_monotonic_time + state.latency + ts_diff

    send_after_timeout =
      (desired_time - Membrane.Time.monotonic_time())
      |> max(0)
      |> Membrane.Time.as_milliseconds(:round)

    Process.send_after(state.parent_process, {:processed_buffer, buffer}, send_after_timeout)

    state
  end

  defp handle_first_buffer(buffer, state) do
    %{
      state
      | first_buffer_ts: buffer.pts,
        first_buffer_monotonic_time: Membrane.Time.monotonic_time()
    }
  end
end
