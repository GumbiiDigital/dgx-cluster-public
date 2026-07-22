# Open-Rack Thermal Management

## Design

The rack was left open deliberately. Access to the Sparks, power supplies, cables, and fabric mattered more than presenting a sealed cabinet.

The lower rack area initially concentrated power bricks and cable loops near the floor. The response had two parts:

1. raise and organize the power supplies in printed rack supports; and
2. place a small floor fan in front of the rack, aimed upward through the open shelves.

Raising the bricks improved service access and removed a dense pile from the lowest warm pocket. The fan was intended to break up stagnant air and move room air upward through the rack.

This was not a CFM measurement, an airflow calibration, or a sealed-system cooling design.

## Control separation

The fan had its own addressable environmental outlet. Compute and infrastructure loads remained continuous-power roles and were not attached to temperature programs.

The design boundary was intentional:

- the environmental outlet could be commissioned independently;
- Spark power behavior could not be triggered by rack temperature;
- infrastructure outlets were excluded from testing; and
- a missing sensor value or alarm would resolve to fan ON, not fan OFF.

Exact controller and outlet labels are omitted from the public record.

## Planned differential test

The short test plan was:

1. hold the Spark workload state as steady as practical;
2. record the single rack probe's starting temperature and humidity;
3. switch only the fan OFF and physically verify it stopped;
4. sample the same probe at a fixed interval for a short baseline window;
5. switch only the fan ON and physically verify it ran;
6. sample for the same duration; and
7. compare the OFF and ON averages, ranges, and timestamps.

Spark internal temperature and rack-probe temperature were kept separate. The former was a workload indicator in Celsius; the latter was the rack-environment observation in Fahrenheit.

## Recorded outcome

The differential test was deferred. The owner chose to keep the fan continuously ON, and the controller telemetry read path was intermittent. No threshold was changed and no complete, matched OFF/ON data set was captured.

Therefore this repository does not claim:

- a measured cooling delta;
- automatic temperature control;
- a proven hysteresis rule;
- long-term thermal capacity; or
- a maximum safe workload temperature for the room or rack.

The defensible result is narrower: the power supplies were raised, the open-rack airflow path was improved, and a dedicated fan was positioned to move room air upward. The intended measurement method is documented, but the result remains unknown.
