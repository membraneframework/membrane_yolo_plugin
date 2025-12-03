defmodule Membrane.YOLO.Detector.Implementations.LiveLowLatency do
  @behaviour Membrane.YOLO.Detector.Implementation

  alias Membrane.YOLO.Detector.Implementations.Utils
  alias Membrane.YOLO.Detector.State

  @impl true
  def handle_buffer(buffer, ctx, %State{} = state) do
    if not state.detection_in_progress? do
      Utils.start_link_detection_task(buffer, ctx, state)
    end

    state = %{state | detection_in_progress?: true}

    buffer =
      buffer
      |> Utils.update_buffer_metadata(state.last_detection_results)

    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_info({:detection_complete, detected_objects}, _ctx, %State{} = state) do
    state = %{state | last_detection_results: detected_objects, detection_in_progress?: false}
    {[], state}
  end

  @impl true
  def handle_end_of_stream(_ctx, %State{} = state) do
    {[end_of_stream: :output], state}
  end
end
