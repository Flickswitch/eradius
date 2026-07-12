defmodule PromExEradius do
  @moduledoc """
  PromEx plugin for [eradius](https://github.com/Flickswitch/eradius) telemetry metrics.

  ## Options

  * `:metric_prefix` - list of atoms prepended to every metric name.
    Defaults to `[:eradius]`.
  * `:duration_buckets` - histogram bucket upper bounds in **milliseconds**
    for observe/duration distributions. Defaults match eradius
    `histogram_buckets` app env: `[10, 30, 50, 75, 100, 1000, 2000]`.
  * `:counters` - list of counter atoms to expose from
    `[:eradius, :inc_counter, counter]`. Defaults to a built-in set covering
    NAS + client counters used by eradius.
  * `:histograms` - list of observe metric atoms (third element of
    `[:eradius, :observe, name]`). Defaults to server + client duration metrics.
  * `:keep` - optional 1-arity function `(metadata -> boolean)` applied to all
    event metrics for filtering.

  ## Example

      def plugins do
        [
          {PromExEradius, metric_prefix: [:my_app, :eradius]}
        ]
      end
  """

  use PromEx.Plugin

  @default_duration_buckets [10, 30, 50, 75, 100, 1000, 2000]

  @default_counters [
    :requests,
    :replies,
    :dupRequests,
    :malformedRequests,
    :accessRequests,
    :accessAccepts,
    :accessRejects,
    :accessChallenges,
    :badAuthenticators,
    :packetsDropped,
    :unknownTypes,
    :handlerFailure,
    :coaRequests,
    :coaAcks,
    :coaNaks,
    :discRequests,
    :discAcks,
    :discNaks,
    :retransmissions,
    :pending,
    :timeouts,
    :invalidRequests,
    :discardNoHandler,
    :accountRequestsStart,
    :accountRequestsStop,
    :accountRequestsUpdate,
    :accountResponsesStart,
    :accountResponsesStop,
    :accountResponsesUpdate
  ]

  @default_histograms [
    :eradius_request_duration_milliseconds,
    :eradius_access_request_duration_milliseconds,
    :eradius_accounting_request_duration_milliseconds,
    :eradius_coa_request_duration_milliseconds,
    :eradius_disconnect_request_duration_milliseconds,
    :eradius_client_request_duration_milliseconds,
    :eradius_client_reply_duration_milliseconds,
    :eradius_client_access_request_duration_milliseconds,
    :eradius_client_accounting_request_duration_milliseconds,
    :eradius_client_coa_request_duration_milliseconds,
    :eradius_client_disconnect_request_duration_milliseconds
  ]

  @impl true
  def event_metrics(opts) do
    metric_prefix = Keyword.get(opts, :metric_prefix, [:eradius])
    buckets = Keyword.get(opts, :duration_buckets, @default_duration_buckets)
    counters = Keyword.get(opts, :counters, @default_counters)
    histograms = Keyword.get(opts, :histograms, @default_histograms)
    keep = Keyword.get(opts, :keep)

    [
      counter_metrics(metric_prefix, counters, keep),
      pending_dec_metrics(metric_prefix, keep),
      histogram_metrics(metric_prefix, histograms, buckets, keep),
      boolean_metrics(metric_prefix, keep)
    ]
  end

  defp counter_metrics(prefix, counters, keep) do
    Event.build(
      :eradius_counter_event_metrics,
      Enum.map(counters, fn counter ->
        event = [:eradius, :inc_counter, counter]
        name = prefix ++ [counter_metric_name(counter), :total]

        counter(
          name,
          metric_opts(
            event_name: event,
            description: "eradius #{counter} increments",
            tags: tag_keys_for_counter(),
            tag_values: &tag_values/1,
            keep: keep
          )
        )
      end)
    )
  end

  # pending is also decremented; expose decs so operators can compute net pending
  defp pending_dec_metrics(prefix, keep) do
    Event.build(
      :eradius_pending_dec_event_metrics,
      [
        counter(
          prefix ++ [:pending, :decrements, :total],
          metric_opts(
            event_name: [:eradius, :dec_counter, :pending],
            description: "eradius pending decrements (pair with pending_total incs)",
            tags: tag_keys_for_counter(),
            tag_values: &tag_values/1,
            keep: keep
          )
        )
      ]
    )
  end

  defp histogram_metrics(prefix, histograms, buckets, keep) do
    Event.build(
      :eradius_histogram_event_metrics,
      Enum.map(histograms, fn hist ->
        event = [:eradius, :observe, hist]
        name = prefix ++ [hist_metric_name(hist)]

        distribution(
          name,
          metric_opts(
            event_name: event,
            measurement: :value,
            description: "eradius histogram #{hist}",
            reporter_options: [buckets: buckets],
            tags: tag_keys_for_histogram(),
            tag_values: &tag_values/1,
            unit: {:native, :millisecond},
            keep: keep
          )
        )
      end)
    )
  end

  defp boolean_metrics(prefix, keep) do
    Event.build(
      :eradius_boolean_event_metrics,
      [
        last_value(
          prefix ++ [:server, :status],
          metric_opts(
            event_name: [:eradius, :boolean, :server_status],
            measurement: fn measurements, _meta ->
              case Map.get(measurements, :value) do
                true -> 1
                false -> 0
                other when is_integer(other) -> other
                _ -> 0
              end
            end,
            description: "Upstream RADIUS server status (1=active, 0=inactive)",
            tags: [:labels],
            tag_values: &boolean_tag_values/1,
            keep: keep
          )
        )
      ]
    )
  end

  # Telemetry.Metrics rejects keep: nil — only include when set
  defp metric_opts(opts) do
    case Keyword.pop(opts, :keep) do
      {nil, rest} -> rest
      {keep_fun, rest} when is_function(keep_fun, 1) -> Keyword.put(rest, :keep, keep_fun)
    end
  end

  defp counter_metric_name(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp hist_metric_name(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace_prefix("eradius_", "")
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp tag_keys_for_counter do
    [
      :server_name,
      :server_ip,
      :server_port,
      :nas_ip,
      :nas_id,
      :client_name,
      :client_ip,
      :client_port
    ]
  end

  defp tag_keys_for_histogram do
    tag_keys_for_counter()
  end

  defp tag_values(meta) when is_map(meta) do
    %{
      server_name: stringify(Map.get(meta, :server_name)),
      server_ip: stringify_ip(Map.get(meta, :server_ip)),
      server_port: stringify(Map.get(meta, :server_port)),
      nas_ip: stringify_ip(Map.get(meta, :nas_ip)),
      nas_id: stringify(Map.get(meta, :nas_id)),
      client_name: stringify(Map.get(meta, :client_name)),
      client_ip: stringify_ip(Map.get(meta, :client_ip)),
      client_port: stringify(Map.get(meta, :client_port))
    }
  end

  defp tag_values(_), do: tag_values(%{})

  defp boolean_tag_values(meta) when is_map(meta) do
    labels =
      case Map.get(meta, :labels) do
        list when is_list(list) ->
          list
          |> Enum.map(&stringify/1)
          |> Enum.join(",")

        other ->
          stringify(other)
      end

    %{labels: labels}
  end

  defp boolean_tag_values(_), do: %{labels: ""}

  defp stringify(nil), do: ""
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_integer(v), do: Integer.to_string(v)
  defp stringify(v), do: inspect(v)

  defp stringify_ip(nil), do: ""
  defp stringify_ip(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      charlist when is_list(charlist) -> List.to_string(charlist)
      other -> stringify(other)
    end
  end
  defp stringify_ip(ip), do: stringify(ip)
end
