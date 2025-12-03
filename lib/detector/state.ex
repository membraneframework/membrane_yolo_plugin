defmodule Membrane.YOLO.Detector.State do
  @moduledoc false

  @enforce_keys [:yolo_model, :mode, :additional_latency, :impl]
  defstruct @enforce_keys ++
              [
                first_buffer_ts: nil,
                first_buffer_monotonic_time: nil,
                last_detection_results: nil,
                buffers_qex: Qex.new(),
                detection_in_progress?: false
              ]

  @type t :: %__MODULE__{}
end
