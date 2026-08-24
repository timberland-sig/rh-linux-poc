def cidr_to_netmask(cidr: int) -> str:
    """Convert CIDR prefix length to dotted decimal netmask."""
    mask = (0xffffffff >> (32 - cidr)) << (32 - cidr)
    return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"