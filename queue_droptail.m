function [admitted, overflowDrops] = queue_droptail(arrivals, queueLength, queueCapacity)

availableSlots = max(0, queueCapacity - queueLength);

admitted = min(arrivals, availableSlots);
overflowDrops = arrivals - admitted;

end