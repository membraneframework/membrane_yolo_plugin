defmodule Membrane.YOLO.LiveFilter.ModelRunner do
  @moduledoc false
  use GenServer

  alias Membrane.YOLO.DrawUtils

  defmodule Opts do
    @enforce_keys [
      :yolo_model,
      :draw_boxes?,
      :additional_latency,
      :low_latency_mode?,
      :stream_format,
      :parent_process
    ]

    defstruct @enforce_keys
  end

  def start_link(%__MODULE__.Opts{} = opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def process_buffer(pid, buffer) do
    GenServer.cast(pid, {:process_buffer, buffer})
  end

  @impl true
  def init(%__MODULE__.Opts{} = opts) do
    state =
      Map.from_struct(opts)
      |> Map.merge(%{
        detection_in_progress?: false,
        buffers_qex: Qex.new(),
        first_buffer_ts: nil,
        first_buffer_monotonic_time: nil,
        last_detection_results: nil
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

    state =
      cond do
        state.low_latency_mode? and state.last_detection_results != nil ->
          buffer
          |> draw_boxes_or_update_metadata(state)
          |> send_buffer(state)

        state.low_latency_mode? ->
          buffer
          |> send_buffer(state)

        not state.low_latency_mode? ->
          state
          |> Map.update!(:buffers_qex, &Qex.push(&1, buffer))
      end

    {:noreply, %{state | detection_in_progress?: true}}
  end

  @impl true
  def handle_cast({:detection_complete, detected_objects}, state) do
    old_buffers_qex = state.buffers_qex

    state = %{
      state
      | detection_in_progress?: false,
        buffers_qex: Qex.new(),
        last_detection_results: detected_objects
    }

    state =
      old_buffers_qex
      |> Enum.reduce(state, fn buffer, state ->
        buffer
        |> draw_boxes_or_update_metadata(state)
        |> send_buffer(state)
      end)

    {:noreply, state}
  end

  defp draw_boxes_or_update_metadata(buffer, state) do
    DrawUtils.draw_boxes_or_update_metadata(
      buffer,
      state.last_detection_results,
      state.stream_format,
      state.draw_boxes?
    )
  end

  @zero_seconds Membrane.Time.seconds(0)
  defp send_buffer(buffer, state) when state.additional_latency in [nil, @zero_seconds] do
    send(state.parent_process, {:processed_buffer, buffer})
    state
  end

  defp send_buffer(buffer, state) do
    state =
      if state.first_buffer_ts == nil,
        do: handle_first_buffer(buffer, state),
        else: state

    ts_diff = buffer.pts - state.first_buffer_ts
    desired_time = state.first_buffer_monotonic_time + state.additional_latency + ts_diff

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
