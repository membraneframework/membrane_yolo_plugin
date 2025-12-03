defmodule Membrane.YOLO.Detector.Implementations.Live do
  @behaviour Membrane.YOLO.Detector.Implementation

  alias Membrane.YOLO.Detector.Implementations.Utils
  alias Membrane.YOLO.Detector.State

  @impl true
  def handle_buffer(buffer, ctx, %State{} = state) do
    if not state.detection_in_progress? do
      Utils.start_link_detection_task(buffer, ctx, state)
    end

    state =
      %{state | detection_in_progress?: true}
      |> Map.update!(:buffers_qex, &Qex.push(&1, buffer))

    {[], state}
  end

  @impl true
  def handle_info({:detection_complete, detected_objects}, _ctx, %State{} = state) do
    state =
      state.buffers_qex
      |> Enum.reduce(state, fn buffer, state ->
        buffer
        |> Utils.update_buffer_metadata(detected_objects)
        |> send_after_to_myself(state)
      end)

    state = %{state | buffers_qex: Qex.new(), detection_in_progress?: false}
    {[], state}
  end

  @impl true
  def handle_info({:processed_buffer, buffer}, ctx, %State{} = state) do
    state = state |> Map.update!(:awaiting_buffers_count, &(&1 - 1))

    maybe_eos =
      if state.awaiting_buffers_count == 0 and ctx.pads.input.end_of_stream?,
        do: [end_of_stream: :output],
        else: []

    {[buffer: {:output, buffer}] ++ maybe_eos, state}
  end

  @impl true
  def handle_end_of_stream(_ctx, %State{} = state) do
    {[], state}
  end

  defp send_after_to_myself(buffer, state) do
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

    Process.send_after(
      self(),
      {:processed_buffer, buffer},
      send_after_timeout
    )

    state |> Map.update!(:awaiting_buffers_count, &(&1 + 1))
  end

  defp handle_first_buffer(buffer, %State{} = state) do
    %{
      state
      | first_buffer_ts: buffer.pts,
        first_buffer_monotonic_time: Membrane.Time.monotonic_time()
    }
  end
end
