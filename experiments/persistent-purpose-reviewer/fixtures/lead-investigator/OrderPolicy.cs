public static class OrderPolicy
{
    public static bool CanOrder(int stock, int requested, bool isSuspended)
    {
        return stock >= requested;
    }

    public static decimal ShippingFee(decimal subtotal)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(subtotal);

        return subtotal >= 100m ? 0m : 5m;
    }
}
