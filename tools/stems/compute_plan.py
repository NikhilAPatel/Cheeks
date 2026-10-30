#!/usr/bin/env python3
"""Reports which compute device Core ML assigns each operation to (MLComputePlan), by op count
and by Core ML's estimated cost share.

    python compute_plan.py path/to/Stems.mlpackage [ALL CPU_AND_GPU CPU_AND_NE CPU_ONLY]
"""

import collections
import sys

import coremltools as ct
from coremltools.models.compute_plan import MLComputePlan


def device_name(usage):
    if usage is None:
        return "none"
    return type(usage.preferred_compute_device).__name__.replace("ML", "").replace("ComputeDevice", "")


def report(package, unit_name):
    unit = getattr(ct.ComputeUnit, unit_name)
    model = ct.models.MLModel(package, compute_units=unit, skip_model_load=False)
    plan = MLComputePlan.load_from_path(model.get_compiled_model_path(), compute_units=unit)
    function = plan.model_structure.program.functions["main"]

    ops = collections.Counter()
    cost = collections.Counter()
    by_type = collections.defaultdict(collections.Counter)
    order = []
    for op in function.block.operations:
        if op.operator_name in ("const",):
            continue
        usage = plan.get_compute_device_usage_for_mlprogram_operation(op)
        estimated = plan.get_estimated_cost_for_mlprogram_operation(op)
        name = device_name(usage)
        ops[name] += 1
        cost[name] += estimated.weight if estimated is not None else 0
        by_type[op.operator_name][name] += 1
        order.append(name)

    print(f"== {unit_name}: {sum(ops.values())} non-const ops")
    total_cost = sum(cost.values()) or 1
    for name, count in ops.most_common():
        print(f"   {name:12s} {count:5d} ops, {100 * cost[name] / total_cost:5.1f}% of estimated cost")
    switches = sum(1 for a, b in zip(order, order[1:]) if a != b)
    print(f"   device switches along program order: {switches}")
    return by_type


def main():
    package = sys.argv[1]
    units = sys.argv[2:] or ["ALL", "CPU_AND_GPU", "CPU_AND_NE", "CPU_ONLY"]
    for unit in units:
        by_type = report(package, unit)
        if unit in ("ALL", "CPU_AND_NE"):
            for op, counter in sorted(by_type.items()):
                print(f"     {op:32s} {dict(counter)}")


if __name__ == "__main__":
    main()
