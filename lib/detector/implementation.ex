defmodule Membrane.YOLO.Detector.Implementation do
  @moduledoc false

  alias Membrane.Element.CallbackContext
  alias Membrane.YOLO.Detector.Implementations
  alias Membrane.YOLO.Detector.State

  @callback handle_buffer(Membrane.Buffer.t(), CallbackContext.t(), State.t()) ::
              {keyword(), State.t()}

  @callback handle_info(message :: any(), CallbackContext.t(), State.t()) ::
              {keyword(), State.t()} | no_return()

  @callback handle_end_of_stream(CallbackContext.t(), State.t()) ::
              {keyword(), State.t()}

  @spec resolve_implementation(mode :: :offline | :live | :live_low_latency) :: module()
  def resolve_implementation(:offline), do: Implementations.Offline
  def resolve_implementation(:live), do: Implementations.Live
  def resolve_implementation(:live_low_latency), do: Implementations.LiveLowLatency
end
