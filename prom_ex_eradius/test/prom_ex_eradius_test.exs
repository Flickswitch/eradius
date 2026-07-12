defmodule PromExEradiusTest do
  use ExUnit.Case, async: true

  alias PromEx.MetricTypes.Event
  alias Telemetry.Metrics.{Counter, Distribution, LastValue}

  describe "event_metrics/1" do
    test "returns four Event metric groups with defaults" do
      groups = PromExEradius.event_metrics([])

      assert length(groups) == 4
      assert Enum.all?(groups, &match?(%Event{}, &1))

      group_names = Enum.map(groups, & &1.group_name)

      assert :eradius_counter_event_metrics in group_names
      assert :eradius_pending_dec_event_metrics in group_names
      assert :eradius_histogram_event_metrics in group_names
      assert :eradius_boolean_event_metrics in group_names
    end

    test "counter metrics target eradius inc_counter events" do
      [%Event{metrics: metrics} | _] = PromExEradius.event_metrics(counters: [:requests])

      assert [%Counter{event_name: [:eradius, :inc_counter, :requests]} = c | _] = metrics
      assert c.tags == [
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

    test "respects metric_prefix" do
      [counter_group | _] =
        PromExEradius.event_metrics(metric_prefix: [:my_app, :radius], counters: [:requests])

      [%Counter{name: name} | _] = counter_group.metrics
      assert [:my_app, :radius, :requests, :total] = name
    end

    test "histogram metrics use observe events and native millisecond unit" do
      groups = PromExEradius.event_metrics(histograms: [:eradius_request_duration_milliseconds])
      hist_group = Enum.find(groups, &(&1.group_name == :eradius_histogram_event_metrics))

      assert [%Distribution{} = d] = hist_group.metrics
      assert d.event_name == [:eradius, :observe, :eradius_request_duration_milliseconds]
      # Telemetry.Metrics converts native→ms into a measurement fun + unit :millisecond
      assert is_function(d.measurement, 1) or d.measurement == :value
      assert d.unit in [:millisecond, {:native, :millisecond}]
    end

    test "boolean metrics map server_status last_value" do
      groups = PromExEradius.event_metrics([])
      bool_group = Enum.find(groups, &(&1.group_name == :eradius_boolean_event_metrics))

      assert [%LastValue{} = lv] = bool_group.metrics
      assert lv.event_name == [:eradius, :boolean, :server_status]
    end
  end

  describe "tag_values via live telemetry attach" do
    test "counter event is handled when telemetry fires" do
      ref = make_ref()
      test_pid = self()
      handler_id = "prom-ex-eradius-test-#{inspect(ref)}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:eradius, :inc_counter, :requests],
          fn event, measurements, metadata, _config ->
            send(test_pid, {:telem, event, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :telemetry.execute(
        [:eradius, :inc_counter, :requests],
        %{},
        %{
          server_name: :root,
          server_ip: {127, 0, 0, 1},
          server_port: 1812,
          nas_ip: {127, 0, 0, 1},
          nas_id: "nas1"
        }
      )

      assert_receive {:telem, [:eradius, :inc_counter, :requests], %{}, meta}
      assert meta.server_port == 1812
      assert meta.nas_id == "nas1"
    end
  end
end
