enum ModelBrowserSectionNavigation {
    static func destination(from section: ModelBrowserSection, movingRight: Bool,
                            rightToLeft: Bool = false) -> ModelBrowserSection {
        let sections = ModelBrowserSection.allCases
        guard let index = sections.firstIndex(of: section) else { return section }
        let step = movingRight != rightToLeft ? 1 : -1
        return sections[(index + step + sections.count) % sections.count]
    }
}
