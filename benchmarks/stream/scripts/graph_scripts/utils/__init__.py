if __name__ == "graph_scripts.utils":
    from graph_scripts.utils.files import file_exists
    from graph_scripts.utils.human_readable import (
        int_to_human,
        scientific_notation,
    )
    from graph_scripts.utils.smoothing import smooth_line
else:
    from utils.files import file_exists
    from utils.human_readable import (
        int_to_human,
        scientific_notation,
    )
    from utils.smoothing import smooth_line


__all__ = (file_exists, int_to_human, scientific_notation, smooth_line)
