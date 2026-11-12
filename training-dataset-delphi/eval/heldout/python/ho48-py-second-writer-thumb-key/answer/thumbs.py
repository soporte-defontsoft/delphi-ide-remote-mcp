"""Keys of the thumbnail cache."""


def thumb_key(photo_id, width):
    """The cache key of a photo's thumbnail of one width."""
    return f"thumb/{photo_id}/w{width}"


def gallery_thumb_key(photo_id, width):
    """The key the gallery stores when it renders a thumbnail: THE thumbnail key, from its one writer."""
    return thumb_key(photo_id, width)


def parse_thumb_key(key):
    """(photo_id, width) of a thumbnail key, or None when it is not one."""
    parts = key.split("/")
    if len(parts) != 3 or parts[0] != "thumb" or not parts[1].isdigit():
        return None
    if not parts[2].startswith("w") or not parts[2][1:].isdigit():
        return None
    return int(parts[1]), int(parts[2][1:])
